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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

import 'session_store.dart';

/// The open chat's history window as its readers see it: whether older
/// rows are still loading, waiting them out, a visible index mapped to the
/// whole chat, and ⌘F find-in-chat. Find lives beside the backfill it waits
/// on: a count taken mid-backfill would disagree with the list.
class ContextWindow {
  ContextWindow(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  AppDatabase get _db => _d.services.db();
  SessionHistoryWindow get _history => _store.history;

  bool get isBackfillingHistory => _history.isBackfilling;
  bool get hasOlderHistory => _history.hasMore;

  /// True when the picker must open. Uses the card's UUID internally —
  /// the home tap handler must not pass that UUID to `getSessionsForId`.
  Future<bool> hasMultipleSavedSessions(CharacterCard card) async {
    final id = card.dbId;
    if (id == null) return true;
    return (await _db.countSessionsForCharacter(id)) > 1;
  }

  Future<void> awaitHistoryHydrated() async {
    final pending = _history.backfill;
    if (pending != null) await pending;
  }

  /// Map a visible-list index to the post-backfill index. Captures the
  /// absolute position *before* awaiting so a fork/delete tap during the
  /// window still addresses the same row after older lines prepend.
  Future<int?> resolveHydratedIndex(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= _session.messages.length) {
      return null;
    }
    final abs = persistMessagePosition(
      base: _history.basePosition,
      index: messageIndex,
    );
    await awaitHistoryHydrated();
    if (abs < 0 || abs >= _session.messages.length) return null;
    return abs;
  }

  /// Scan the OPEN session's visible text for the find bar. Waits for the
  /// history backfill first (partial results are not usable — same
  /// [awaitHistoryHydrated] contract RAG and Journal honour), so hit
  /// indices and the rendered list can never disagree from a prepend.
  /// Status banners are skipped: they render through their own widget, so a
  /// count with no highlight would break "search what you see".
  Future<ChatFindOutcome> findInTranscript(
    String query, {
    bool regexMode = false,
    bool caseSensitive = false,
  }) async {
    final epoch = _history.epoch;
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return const ChatFindOutcome();
    final spec = compileChatQuery(
      query,
      regexMode: regexMode,
      caseSensitive: caseSensitive,
    );
    if (spec.bad) return const ChatFindOutcome(badPattern: true);
    await awaitHistoryHydrated();
    if (epoch != _history.epoch || _session.currentSessionId != sessionId) {
      return const ChatFindOutcome(stale: true);
    }
    final visible = [
      for (final m in _session.messages)
        (text: m.isStatusBanner ? '' : m.displayText, sender: m.sender),
    ];
    // A plain query is an escaped literal and cannot backtrack. A raw regex
    // can, and so can a many-star glob on a long unbroken token, so both
    // run on the killable isolate.
    final List<ChatFindMatch>? matches;
    try {
      matches = regexMode || spec.wordBounded
          ? await scanTranscriptBounded(
              visible,
              query,
              regexMode: regexMode,
              caseSensitive: caseSensitive,
            )
          : scanTranscript(visible, spec);
    } on StateError catch (e) {
      // The pattern compiled but the scan itself failed: say "bad pattern"
      // rather than pretending it was merely slow.
      debugPrint('find-in-chat: $e');
      return const ChatFindOutcome(badPattern: true);
    }
    if (epoch != _history.epoch || _session.currentSessionId != sessionId) {
      return const ChatFindOutcome(stale: true);
    }
    if (matches == null) {
      return ChatFindOutcome(tooSlow: true, totalMessages: visible.length);
    }
    return ChatFindOutcome(
      matches: matches,
      capped: matches.length >= kFindMatchCap,
      totalMessages: visible.length,
    );
  }

  /// Session total for the backfill-wait progress line ("2,400 / 11,382").
  /// Cheap COUNT; the backfill itself only notifies when it finishes, so the
  /// bar polls loaded-vs-total while it waits.
  Future<int> countAllMessages() async {
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return 0;
    return _db.countMessagesForSession(sessionId);
  }
}
