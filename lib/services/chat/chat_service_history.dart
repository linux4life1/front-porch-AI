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
/// many turns between evictions. Stateless: the boundary is derived from the
/// drop index alone, so regen/swipe/reload all land on the same boundary.
const int kHistoryTrimChunk = 8;

/// Private prompt chat-history builders and token counting/budgeting. Pure
/// formatting over `_messages` plus token accounting — no orchestration or
/// engine logic — extracted verbatim from `chat_service.dart` (zero behaviour
/// change) to shrink the god file. Private members, so safe to move to an
/// extension (never part of the public interface / fakeable).
extension ChatServiceHistory on ChatService {
  /// One history line per message (shared by both history builders so they
  /// can never drift). Director notes get bracketed so the AI treats them as
  /// instructions; generated-image messages (empty text + image metadata from
  /// `/image` or the studio's Send to chat) are described briefly instead of
  /// producing a bare "Sender:" line; user-attached photos are marked (with
  /// the stored auto-caption once available) so turns after the pixels stop
  /// riding along still know a photo was shared and what it showed.
  String _formatHistoryLine(ChatMessage m) {
    if (m.characterId == '__director__') {
      return '[Director: ${m.text}]';
    }
    if (m.activeMetadata?['is_user_image'] == true) {
      final caption = (m.activeMetadata?['image_caption'] as String? ?? '')
          .trim();
      final attach = '[attaches a photo${caption.isEmpty ? '' : ': $caption'}]';
      final text = m.text.trim();
      return '${m.sender}: ${text.isEmpty ? attach : '$text $attach'}';
    }
    if (m.activeMetadata?['is_generated_image'] == true && m.text.isEmpty) {
      final prompt = (m.activeMetadata?['image_prompt'] as String? ?? '')
          .trim();
      final short = prompt.length > 120
          ? '${prompt.substring(0, 120)}…'
          : prompt;
      return '${m.sender}: [shares a generated image'
          '${short.isEmpty ? '' : ': $short'}]';
    }
    return '${m.sender}: ${m.text}';
  }

  String _buildChatHistory({List<LoreDepthEntry> depthLore = const []}) {
    final lines = _messages.map(_formatHistoryLine).toList();
    if (lines.any((l) => ChatService._macroPattern.hasMatch(l))) {
      debugPrint('[MacroResolver] ⚠ Unresolved macro detected in chat history');
    }
    return _spliceDepthLore(lines, depthLore).join("\n");
  }

  /// Insert @depth lore entries into a history line list: depth N = N
  /// message-lines up from the end (0 = after the last message), clamped.
  /// Entries sharing a depth keep their bucket order.
  List<String> _spliceDepthLore(
    List<String> lines,
    List<LoreDepthEntry> depthLore,
  ) {
    if (depthLore.isEmpty) return lines;
    final atFromEnd = <int, List<String>>{};
    for (final d in depthLore) {
      final clamped = d.depth > lines.length ? lines.length : d.depth;
      atFromEnd.putIfAbsent(clamped, () => []).add(d.content);
    }
    final out = <String>[];
    for (var i = 0; i <= lines.length; i++) {
      final insert = atFromEnd[lines.length - i];
      if (insert != null) out.addAll(insert);
      if (i < lines.length) out.add(lines[i]);
    }
    return out;
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
    if (formatted.any((l) => ChatService._macroPattern.hasMatch(l))) {
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
      if (usedTokens + msgTokens > tokenBudget && included.isNotEmpty) {
        // This message would exceed budget — drop it and all older messages
        droppedCount = i + 1;
        break;
      }
      usedTokens += msgTokens;
      included.insert(0, msgText);
    }

    // Sticky trimming (kHistoryTrimChunk): quantize the drop point UP to the
    // next chunk boundary so the surviving prefix stays identical for up to
    // a chunk of turns — the prefix-cache win. Never evicts the newest
    // message (clamp), and the freed margin is simply unused budget that
    // refills before the next eviction.
    if (droppedCount > 0) {
      final quantized =
          ((droppedCount + kHistoryTrimChunk - 1) ~/ kHistoryTrimChunk) *
          kHistoryTrimChunk;
      final capped = quantized.clamp(0, formatted.length - 1);
      if (capped > droppedCount) {
        for (int i = droppedCount; i < capped; i++) {
          usedTokens -= counted[i];
        }
        included.removeRange(0, capped - droppedCount);
        droppedCount = capped;
      }
    }

    final spliced = _spliceDepthLore(included, depthLore);

    // If messages were dropped, prepend a separator
    String history = spliced.join('\n');
    if (droppedCount > 0) {
      history =
          '[Earlier messages truncated — see summary above for context]\n$history';
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
