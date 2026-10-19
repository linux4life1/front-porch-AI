// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Outcome of one ⌘F find pass. [stale] means the session or the history
/// epoch moved under the scan (the UI re-runs it); [capped] means hit
/// collection stopped at [kFindMatchCap] and the counter must read "999+".
class ChatFindOutcome {
  final bool badPattern;
  final bool stale;
  final bool capped;
  final List<ChatFindMatch> matches;
  final int totalMessages;
  const ChatFindOutcome({
    this.badPattern = false,
    this.stale = false,
    this.capped = false,
    this.matches = const [],
    this.totalMessages = 0,
  });
}

extension ChatServiceFind on ChatService {
  /// Scan the OPEN session's visible text for the find bar. Waits for the
  /// history backfill first (partial results are not usable — same
  /// [_awaitHistoryHydrated] contract RAG and Journal honour), so hit
  /// indices and the rendered list can never disagree from a prepend.
  /// Status banners are skipped: they render through their own widget, so a
  /// count with no highlight would break "search what you see".
  Future<ChatFindOutcome> findInTranscript(
    String query, {
    bool regexMode = false,
    bool caseSensitive = false,
  }) async {
    final epoch = _history.epoch;
    final sessionId = _currentSessionId;
    if (sessionId == null) return const ChatFindOutcome();
    final spec = compileChatQuery(
      query,
      regexMode: regexMode,
      caseSensitive: caseSensitive,
    );
    if (spec.bad) return const ChatFindOutcome(badPattern: true);
    await _awaitHistoryHydrated();
    if (epoch != _history.epoch || _currentSessionId != sessionId) {
      return const ChatFindOutcome(stale: true);
    }
    final matches = scanTranscript([
      for (final m in _messages)
        (text: m.isStatusBanner ? '' : m.displayText, sender: m.sender),
    ], spec);
    return ChatFindOutcome(
      matches: matches,
      capped: matches.length >= kFindMatchCap,
      totalMessages: _messages.length,
    );
  }

  /// Session total for the backfill-wait progress line ("2,400 / 11,382").
  /// Cheap COUNT; the backfill itself only notifies when it finishes, so the
  /// bar polls loaded-vs-total while it waits.
  Future<int> countAllMessages() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return 0;
    return _db.countMessagesForSession(sessionId);
  }
}
