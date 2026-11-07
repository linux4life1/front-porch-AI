// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'session_store.dart';

/// Tail-first session hydrate, then a chunked background backfill of
/// everything older. The tail is what ChatPage paints; the rest pages in
/// with a yield per chunk so 11k JSON decodes cannot freeze the first
/// paint. Overlay drop belongs to the owner after scalars hydrate — this
/// must not end the session load. RAG/Journal wait on
/// [ContextWindow.awaitHistoryHydrated] or treat the window's base
/// position as already out of context.
class SessionHydrator {
  SessionHydrator(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  AppDatabase get _db => _s.db();
  SessionHistoryWindow get _history => _store.history;

  /// Last [kSessionOpenWindow] rows, then pages the rest in on a
  /// yielded loop. Does not drop the session overlay — scalars still
  /// hydrate after this returns, and a picker-owned load still has
  /// loadSession / startNewChat to run.
  Future<void> openSessionMessages(String sessionId) async {
    if (_history.backfill != null &&
        _history.backfillSessionId == sessionId &&
        _session.messages.isNotEmpty) {
      debugPrint(
        '[ChatOpen] keep tail; archive load already running '
        'session=$sessionId n=${_session.messages.length}',
      );
      return;
    }
    final sw = Stopwatch()..start();
    _history.reset();
    final tail = await _db.getMessagesTailForSession(
      sessionId,
      kSessionOpenWindow,
    );
    _store.computeAbsenceGap(tail);
    _session.messages.clear();
    hydrateMessagesFromRows(tail);
    if (tail.isNotEmpty) {
      _history.basePosition = tail.first.position;
      _history.hasMore = tail.first.position > 0;
    }
    debugPrint(
      '[ChatOpen] tail ${sw.elapsedMilliseconds}ms '
      'n=${tail.length} base=${_history.basePosition} '
      'hasMore=${_history.hasMore} session=$sessionId',
    );
    if (_history.hasMore) {
      final epoch = _history.epoch;
      _history.backfillSessionId = sessionId;
      _history.backfill = _runBackgroundBackfill(sessionId, epoch);
    }
  }

  Future<void> _runBackgroundBackfill(String sessionId, int epoch) async {
    // The open path still has its own queries (scalars, worlds, quests).
    // Starting the archive scan first queues those behind dozens of
    // message reads and holds the loading cover over the whole chat.
    while (_store.isLoadingSession &&
        epoch == _history.epoch &&
        _session.currentSessionId == sessionId) {
      await Future<void>.delayed(Duration.zero);
    }
    if (epoch != _history.epoch || _session.currentSessionId != sessionId) {
      return;
    }
    // One frame so ChatPage paints the tail before we decode the archive.
    await Future<void>.delayed(Duration.zero);
    final sw = Stopwatch()..start();
    var pages = 0;
    try {
      while (_history.hasMore &&
          epoch == _history.epoch &&
          _session.currentSessionId == sessionId) {
        final more = await _prependOlderPage(sessionId, epoch);
        if (!more) break;
        pages++;
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      if (epoch == _history.epoch) {
        _history.backfill = null;
        if (!_history.hasMore) _d.notify();
      }
      debugPrint(
        '[ChatOpen] backfill ${sw.elapsedMilliseconds}ms '
        'pages=$pages n=${_session.messages.length} session=$sessionId',
      );
    }
  }

  /// One older page. Returns false when the prefix is done or the
  /// session changed. The background loop notifies once at the end so
  /// idle scrolling is not rebuilt on every page.
  Future<bool> _prependOlderPage(String sessionId, int epoch) async {
    if (!_history.hasMore) return false;
    final older = await _db.getMessagesBeforePosition(
      sessionId,
      _history.basePosition,
      limit: kSessionOlderPage,
    );
    if (epoch != _history.epoch || _session.currentSessionId != sessionId) {
      return false;
    }
    if (older.isEmpty) {
      _history.hasMore = false;
      _history.basePosition = 0;
      return false;
    }
    final kept = List<ChatMessage>.from(_session.messages);
    _session.messages.clear();
    hydrateMessagesFromRows(older);
    _session.messages.addAll(kept);
    _history.basePosition = older.first.position;
    _history.hasMore =
        older.length == kSessionOlderPage && older.first.position > 0;
    // After basePosition/hasMore so the last page sees a complete
    // history. A bad stamp cast must not skip the rest of open.
    try {
      _s.clockReader().backfillLoadedSlotClocks();
    } catch (e, st) {
      debugPrint('[Clock] page backfill failed: $e\n$st');
    }
    return _history.hasMore;
  }

  /// One older page for scroll-up. No-op while the background loop
  /// is already paging newest → older, or when the prefix is done.
  Future<void> loadOlderHistory({int count = kSessionOlderPage}) async {
    if (_history.isBackfilling) return;
    final sid = _session.currentSessionId;
    if (sid == null || !_history.hasMore) return;
    await _prependOlderPage(sid, _history.epoch);
    _d.notify();
  }

  /// Decode DB [Message] rows into the session's messages, applying
  /// retroactive output sanitisation when the per-chat or global setting
  /// requests it. Caller must clear the messages and set the per-chat
  /// generation settings beforehand.
  void hydrateMessagesFromRows(List<Message> dbMessages) {
    final storage = _s.storage;
    // Output sanitizer: apply configured replacements to loaded swipes
    // so legacy messages (saved before this feature) are also normalised.
    // Gated by sanitiseExistingHistory — when off, even chats with
    // per-chat sanitizer enabled keep their raw saved text on load.
    // Resolved (per-chat override + rules, falling back to global) and
    // compiled ONCE out here: this loop runs per message and sanitize runs
    // per swipe, so compiling per swipe was thousands of RegExp
    // constructions on the UI isolate per chat open (hot-path rule).
    final compiledRules =
        _store.genSettings.resolveOutputSanitizerEnabled(storage) &&
            storage.generationSettings.sanitiseExistingHistory
        ? compileSanitizerRules(
            _store.genSettings.resolveOutputSanitizerRules(storage),
          )
        : const <CompiledSanitizerRule>[];
    for (final m in dbMessages) {
      List<String> swipes;
      try {
        swipes = List<String>.from(jsonDecode(m.swipes));
      } catch (_) {
        swipes = [''];
      }

      // Model output ONLY — the feature's contract. Without the isUser
      // gate, a broad rule + retroactive-on rewrote the USER's own words in
      // memory, and the next save persisted the corruption. (Impersonate
      // drafts are sanitized at creation time, before they become user rows.)
      // System rows (backend notices, app status) are skipped too — rules
      // rewriting those could break the backend-notice dedupe comparison.
      if (!m.isUser &&
          m.sender != 'System' &&
          compiledRules.isNotEmpty &&
          swipes.isNotEmpty) {
        swipes = swipes
            .map((s) => sanitizeOutputCompiled(s, compiledRules))
            .toList();
      }

      List<int> swipeDurations;
      try {
        swipeDurations = List<int>.from(
          (jsonDecode(m.swipeDurations) as List).map((e) => (e as num).toInt()),
        );
      } catch (_) {
        swipeDurations = [0];
      }

      final safeSwipeIndex = (m.swipeIndex >= 0 && m.swipeIndex < swipes.length)
          ? m.swipeIndex
          : 0;

      _session.messages.add(
        ChatMessage(
          text: swipes.isNotEmpty ? swipes[safeSwipeIndex] : '',
          sender: m.sender,
          isUser: m.isUser,
          characterId: m.characterId,
          swipes: swipes,
          swipeIndex: safeSwipeIndex,
          swipeDurations: swipeDurations,
          metadata: m.metadata != null
              ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
              : null,
          swipeMetadata: m.swipeMetadata != null
              ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                    .map(
                      (e) => e != null
                          ? Map<String, dynamic>.from(e as Map)
                          : null,
                    )
                    .toList()
              : null,
        ),
      );
    }

    if (_session.messages.isNotEmpty) {
      _s.lorebook().scanLatest();
    }
    _s.cast().greetings.restoreGreetingIndex();
  }
}
