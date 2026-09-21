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

part of '../chat_service.dart';

/// Once the context is full, evict oldest messages in CHUNKS of this many
/// instead of one per turn (docs/design/prompt-state-injection.md Phase 3).
/// Dropping exactly one oldest message every turn shifts the history's token
/// prefix EVERY turn, so a local backend's prefix cache (KoboldCpp
/// fast-forward) never matches and the whole transcript re-prefills each
/// message. Rounding the drop point up to a chunk boundary wastes at most a
/// chunk's worth of budget but keeps the prefix byte-stable for up to this
/// many turns between evictions. Layer 1 of sticky trimming — layer 2 is the
/// per-session monotonic [_HistoryAnchor] below, which stops budget wobble
/// from oscillating the drop across a chunk boundary between turns.
const int kHistoryTrimChunk = 8;

/// Per-service history-window anchor (see the monotonic-anchor comment in
/// [_buildChatHistoryWithBudget]). An [Expando] rather than a ChatService
/// field ONLY because the shell sits at the 1,000-line ratchet's edge —
/// per-instance state, garbage-collected with the service, invisible to
/// golden fakes.
class _HistoryAnchor {
  String? session;
  int dropped = 0;
  int budget = 0;
}

final Expando<_HistoryAnchor> _historyAnchorOf = Expando();

/// Private prompt chat-history builders and token counting/budgeting. Pure
/// formatting over `_messages` plus token accounting — no orchestration or
/// engine logic — extracted verbatim from `chat_service.dart` (zero behaviour
/// change) to shrink the god file. Private members, so safe to move to an
/// extension (never part of the public interface / fakeable).
extension ChatServiceHistory on ChatService {
  /// One history line per message (shared by both history builders so they
  /// can never drift). Delegates to [ChatMessage.toPromptHistoryLine] so the
  /// generation prompt and the eval windows ([recentExchange]) agree: think
  /// blocks stay UI-only, photos carry their caption marker, director notes
  /// and generated-image shares keep their brackets.
  String _formatHistoryLine(ChatMessage m) => m.toPromptHistoryLine();

  Iterable<String> _promptHistoryLines(Iterable<String> lines) =>
      lines.where((l) => l.isNotEmpty);

  /// Tiny-context floor: keep the latest user line and everything after it.
  /// A guest chime-in used to keep only `_messages.last` (the host reaction)
  /// and the question the guest was meant to answer vanished.
  ({String history, int droppedCount}) _overflowContinuityHistory() {
    if (_messages.isEmpty) return (history: '', droppedCount: 0);
    final start = overflowHistoryStart(_messages);
    return (
      history: _promptHistoryLines(
        _messages.sublist(start).map(_formatHistoryLine),
      ).join('\n'),
      droppedCount: start,
    );
  }

  String _buildChatHistory({List<LoreDepthEntry> depthLore = const []}) {
    final lines = _messages.map(_formatHistoryLine).toList();
    if (lines.any((l) => _macroPattern.hasMatch(l))) {
      debugPrint('[MacroResolver] ⚠ Unresolved macro detected in chat history');
    }
    return spliceDepthLore(
      _promptHistoryLines(lines).toList(),
      depthLore,
    ).join('\n');
  }

  /// Build chat history that fits within a token budget.
  /// Walks messages newest-to-oldest, dropping the oldest that don't fit.
  /// [depthLore] entries are spliced in AFTER the budget walk (their tokens
  /// were already counted in the fixed content), relative to the included
  /// lines, so lore never evicts the history it positions against.
  /// Returns ({String history, int droppedCount, int tokenCount}).
  Future<({String history, int droppedCount, int tokenCount})>
  _buildChatHistoryWithBudget(
    int tokenBudget, {
    List<LoreDepthEntry> depthLore = const [],
  }) async {
    if (_messages.isEmpty) return (history: '', droppedCount: 0, tokenCount: 0);

    // Format all messages, skipping hidden group realism checkpoints
    final formatted = _messages.map(_formatHistoryLine).toList();
    if (formatted.any((l) => _macroPattern.hasMatch(l))) {
      debugPrint('[MacroResolver] ⚠ Unresolved macro detected in chat history');
    }

    // If budget is very large or negative (unlimited), return everything
    if (tokenBudget <= 0) {
      return (history: formatted.join('\n'), droppedCount: 0, tokenCount: 0);
    }

    // Walk from newest to oldest, accumulating messages that fit
    final included = <String>[];
    final counted = List<int>.filled(formatted.length, 0);
    int usedTokens = 0;
    int droppedCount = 0;

    for (int i = formatted.length - 1; i >= 0; i--) {
      final msgText = formatted[i];
      final msgTokens = await _countTokens(msgText);
      counted[i] = msgTokens;
      if (msgText.isEmpty) {
        continue;
      }
      if (usedTokens + msgTokens > tokenBudget && included.isNotEmpty) {
        // This message would exceed budget — drop it and all older messages
        droppedCount = i + 1;
        break;
      }
      usedTokens += msgTokens;
      included.insert(0, msgText);
    }

    // Sticky trimming, TWO layers — both exist for the prefix cache:
    //
    //  1. kHistoryTrimChunk quantizes the drop point UP to a chunk boundary
    //     so ordinary growth moves the window start only once per chunk of
    //     turns.
    //  2. The MONOTONIC ANCHOR (2026-08-11, maintainer report: oMLX at 2.8%
    //     cache efficiency, ~52k re-prefilled EVERY turn). Quantization
    //     alone re-fits from scratch each turn, so when the post-history
    //     blocks wobble the budget (the journal re-sorts with mood and
    //     re-warms cards per turn, expand-memory flaps ±1k chars, the
    //     set-aside line comes and goes), a raw drop point sitting near a
    //     chunk boundary OSCILLATES across it — and every flip re-prefills
    //     the entire transcript on every prefix-caching backend (oMLX,
    //     KoboldCpp, LM Studio). The anchor makes the window start
    //     monotonic per session: once a message is dropped it STAYS
    //     dropped, so the surviving prefix is byte-stable until the chat
    //     genuinely outgrows the next chunk. The cost is up to one chunk of
    //     messages hidden a few turns earlier than strictly necessary —
    //     covered by the recap, which keys on droppedCount and stays live.
    //     Deliberate resets only: a session switch, a budget that GREW by
    //     >25% (the user raised context — permanently hiding messages the
    //     context now affords would be theft), or an anchor beyond the
    //     message list (a cleared/rewritten chat).
    final anchor = _historyAnchorOf[this] ??= _HistoryAnchor();
    if (anchor.session != _currentSessionId ||
        anchor.dropped >= formatted.length) {
      anchor.session = _currentSessionId;
      anchor.dropped = 0;
      anchor.budget = tokenBudget;
    } else if (tokenBudget > anchor.budget + (anchor.budget >> 2)) {
      // Genuinely more room than this session has EVER had (the user raised
      // the context) — permanently hiding messages it can now afford would
      // be theft. anchor.budget is a HIGH-WATER mark on purpose: comparing
      // against the last-seen budget instead made an ordinary block
      // wobble's downswing+restore read as growth and re-opened the window
      // — the exact oscillation this anchor exists to kill (caught red by
      // history_prefix_stability_test before this ever shipped).
      anchor.dropped = 0;
      anchor.budget = tokenBudget;
    } else if (tokenBudget > anchor.budget) {
      anchor.budget = tokenBudget;
    }

    final effectiveDrop = droppedCount > anchor.dropped
        ? droppedCount
        : anchor.dropped;
    if (effectiveDrop > 0) {
      final quantized =
          ((effectiveDrop + kHistoryTrimChunk - 1) ~/ kHistoryTrimChunk) *
          kHistoryTrimChunk;
      final capped = quantized.clamp(0, formatted.length - 1);
      if (capped > droppedCount) {
        for (int i = droppedCount; i < capped; i++) {
          usedTokens -= counted[i];
        }
        included.removeRange(0, capped - droppedCount);
        droppedCount = capped;
      }
      if (droppedCount > anchor.dropped) {
        debugPrint(
          '[Context] history window advanced to $droppedCount '
          '(prefix re-anchors this turn)',
        );
      }
      anchor.dropped = droppedCount;
    }

    final spliced = spliceDepthLore(included, depthLore);

    // If messages were dropped, prepend a separator
    String history = spliced.join('\n');
    if (droppedCount > 0) {
      history =
          '[Earlier messages truncated — see the recap below for context]\n$history';
    }

    return (
      history: history,
      droppedCount: droppedCount,
      tokenCount: usedTokens,
    );
  }

  /// Count tokens for a text string. Uses KoboldCpp's tokenizer when available,
  /// falls back to chars/4 estimate for remote APIs.
  Future<int> _countTokens(String text) async {
    if (text.isEmpty) return 0;
    // Use the KoboldCpp tokenizer if we're running locally
    if (_llmProvider == null || _llmProvider!.isLocal) {
      return _koboldService.countTokens(text);
    }
    // Fallback for remote APIs
    return (text.length / 4).ceil();
  }
}
