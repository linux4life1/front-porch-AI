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

/// One-shot "Mafia night" force-ack prompt block (Chance Time register).
/// Design: docs/design/llmerta-porch-memories.md §7b.
///
/// Pure text builder — no I/O. High-recency plan slot; [PorchNightAckState]
/// keeps the block available for **regen of the reacting AI message** until
/// the user sends their next turn (then clear).
class PorchNightInjection {
  PorchNightInjection._();

  /// Max fact bullets so the block stays short for local models.
  static const int kMaxBullets = 6;

  /// Build a TABLE TALK force-ack block. Uses `{{user}}` / `{{char}}`
  /// placeholders — resolve with MacroResolver before the model sees it.
  ///
  /// [bullets] are `(emotionLabel, content)` from planted porch cards.
  static String build({
    required List<({String emotion, String content})> bullets,
    String? townName,
  }) {
    if (bullets.isEmpty) return '';

    final taken = bullets.take(kMaxBullets).toList();
    final town = (townName != null && townName.trim().isNotEmpty)
        ? townName.trim()
        : null;
    final townClause = town == null ? '' : ' in $town';

    final lines = StringBuffer();
    lines.writeln(
      '[TABLE TALK — Mafia night is real shared history with {{user}}, '
      'not a metaphor for the current scene:',
    );
    lines.writeln();
    lines.writeln(
      '{{user}} and {{char}} played a finished game of Mafia together$townClause. '
      'This is post-game table talk energy (good game / I can\'t believe / '
      'you bused me / I thought you were Town), not soft atmospheric mood only.',
    );
    lines.writeln();
    lines.writeln(
      'HARD FACTS (use these literally — do NOT invent other roles, votes, '
      'or outcomes not listed):',
    );
    for (final b in taken) {
      final emotion = b.emotion.trim().isEmpty ? 'charged' : b.emotion.trim();
      final content = b.content.trim();
      if (content.isEmpty) continue;
      lines.writeln('- ($emotion) $content');
    }
    lines.writeln();
    lines.writeln(
      'REQUIRED OPENING: the FIRST 2–4 sentences of the reply MUST be clear, '
      'spoken (or strongly voiced) table talk about that Mafia game — e.g. '
      '"good game", calling out a bus or defend, naming sides if the facts '
      'say so ("I thought you were Town"), town name if known. '
      'Do NOT only bury it in internal monologue, exhaustion metaphors, or '
      'winks about the present scene. After that short debrief, continue the '
      'current scene naturally. Never mention game apps, exports, journals, '
      'or systems.]',
    );
    return '\n${lines.toString()}\n';
  }
}

/// Session-scoped force-ack delivery (Chance Time pattern).
///
/// - [takeForPrompt] returns the block and marks *shown* but **keeps** the
///   text so regen/swipe of that AI reply re-injects the same block.
/// - [clearDelivered] runs on the **next user send** after a show — that is
///   the "accepted the turn and continued" gate. Until then, regens still
///   see the block. Cards keep `porchAckPending` until that clear so a
///   process restart mid-window can re-arm from the diary.
class PorchNightAckState {
  /// diaryCharacterId → rendered injection text (pre-macro).
  final Map<String, String> _pending = {};

  /// Shown in at least one prompt this window (regen still allowed).
  final Set<String> _shown = {};

  /// diaryCharacterId → journal card ids that still need porchAckPending cleared.
  final Map<String, List<String>> _cardIdsByDiary = {};

  /// True when this diary owner has a live force-ack block armed.
  bool isArmed(String diaryCharacterId) =>
      (_pending[diaryCharacterId] ?? '').isNotEmpty;

  /// True when the block was included in a generation (regen still re-takes).
  bool wasShown(String diaryCharacterId) => _shown.contains(diaryCharacterId);

  void arm({
    required String diaryCharacterId,
    required String injectionText,
    required List<String> journalCardIds,
  }) {
    if (injectionText.trim().isEmpty) return;
    _pending[diaryCharacterId] = injectionText;
    // Re-arming after re-load must not wipe "shown" if we're mid regen window;
    // only replace text + card ids. Shown state stays so clear-on-next-user still works.
    _cardIdsByDiary[diaryCharacterId] = List<String>.from(journalCardIds);
  }

  /// Return the block for this diary owner. Does **not** remove it (regen-safe).
  String takeForPrompt(String diaryCharacterId) {
    final text = _pending[diaryCharacterId];
    if (text == null || text.isEmpty) return '';
    _shown.add(diaryCharacterId);
    return text;
  }

  /// Card ids for owners whose injection was **shown** (clear metadata after
  /// the user continues past that AI turn).
  List<String> shownCardIds() {
    final ids = <String>[];
    for (final diaryId in _shown) {
      final list = _cardIdsByDiary[diaryId];
      if (list != null) ids.addAll(list);
    }
    return ids;
  }

  /// True when at least one diary had the block shown (safe to clear on user turn).
  bool get hasShownAny => _shown.isNotEmpty;

  /// Clear in-memory state for owners that already **showed** the block.
  /// Call only from the next user [sendMessage] after a show.
  void clearAfterAcceptedUserTurn() {
    final toClear = Set<String>.from(_shown);
    for (final diaryId in toClear) {
      _pending.remove(diaryId);
      _cardIdsByDiary.remove(diaryId);
      _shown.remove(diaryId);
    }
  }
}
