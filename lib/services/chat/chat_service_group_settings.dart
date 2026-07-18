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

/// Per-group-character **settings** — RAG/memory tuning, per-character Author's
/// Note, and per-character system-prompt overrides — stored in the group's
/// in-memory maps. Extracted verbatim from `chat_service.dart` (zero behaviour
/// change) to shrink the god file; as `part of` the same library it reaches the
/// private group maps, `_activeGroup`, `_getCharacterIdFromCard`, and `_saveChat`
/// exactly as the in-class methods did.
extension ChatServiceGroupSettings on ChatService {
  // ── Group RAG / Memory Settings (stored in checkpoint) ───────────────────
  bool get groupRagEnabled => _groupRagEnabled;

  int get groupRetrievalCount => _groupRetrievalCount;

  double get groupMemoryBudgetPercent => _groupMemoryBudgetPercent;

  double getCharacterRAGPriority(String charId) {
    return _groupCharacterRAGPriorities[charId] ?? 1.0;
  }

  Map<String, double> get currentGroupRAGPriorities =>
      Map.unmodifiable(_groupCharacterRAGPriorities);

  void setGroupRAGEnabled(bool value) {
    if (_activeGroup == null) return;
    _groupRagEnabled = value;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void setGroupRetrievalCount(int value) {
    if (_activeGroup == null) return;
    _groupRetrievalCount = value;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void setGroupMemoryBudgetPercent(double value) {
    if (_activeGroup == null) return;
    _groupMemoryBudgetPercent = value;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void setCharacterRAGPriority(String charId, double priority) {
    if (_activeGroup == null) return;
    _groupCharacterRAGPriorities[charId] = priority;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void clearCharacterRAGPriority(String charId) {
    _groupCharacterRAGPriorities.remove(charId);
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  /// Whether the active group currently uses RANDOM turn order (vs round-robin).
  bool get isGroupTurnOrderRandom =>
      _activeGroup?.turnOrder == TurnOrder.random;

  /// Chat-wide "is NSFW Enhancement on" for the group toggle. Reads the STABLE
  /// per-character flag from `_groupRealism` (which `setNsfwCooldownEnabled`
  /// propagates to every member) rather than `_nsfwService.nsfwCooldownEnabled`
  /// — the live scalar is per-speaker-volatile in a group (reset on entry,
  /// overwritten by `loadNsfwScalarsForSpeaker` each turn), so a toggle bound to
  /// it wouldn't reflect the user's choice. Falls back to the scalar (1:1, or
  /// before any member flag exists).
  bool get isGroupNsfwEnabled {
    if (_activeGroup != null) {
      for (final c in _groupCharacters) {
        final v = _groupRealism[_getCharacterIdFromCard(c)]?['nsfwCooldownEnabled'];
        if (v is bool) return v;
      }
    }
    return _nsfwService.nsfwCooldownEnabled;
  }

  /// Set the active group's turn order on the fly (the `/turnorder` macro).
  /// [random] true → a random member answers each turn; false → round-robin.
  /// When [customOrder] is supplied (round-robin only) the live roster is
  /// reordered to that exact sequence so the rotation follows it. The MODE is
  /// persisted on the group; a custom ORDER is session-scoped (the roster reloads
  /// in member-insertion order on next open — there is no per-member sort column).
  Future<void> setGroupTurnOrder(
    bool random,
    List<CharacterCard>? customOrder,
  ) async {
    final group = _activeGroup;
    if (group == null) return;
    group.turnOrder = random ? TurnOrder.random : TurnOrder.roundRobin;
    if (!random && customOrder != null && customOrder.isNotEmpty) {
      _groupManager?.refreshCharacters(customOrder);
    }
    _groupManager?.resetTurnState(); // fresh pointer so the order starts at #1
    await _groupChatRepository?.save(group);
    await _saveChat();
    notifyListeners();
  }

  /// Returns the Author's Note text (if any) stored specifically for this
  /// character within the current *group* chat. Uses the stable char ID.
  /// Returns '' if not in group mode or no per-character note has been set.
  /// (The group's authorNoteStrength is used for formatting during injection.)
  String getAuthorNoteForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return '';
    final id = _getCharacterIdFromCard(c);
    return _groupAuthorNotes[id] ?? '';
  }

  /// Returns the strength (1-10) for this character's Author's Note.
  /// Falls back to the group's current authorNoteStrength if no per-character
  /// strength has been explicitly set.
  int getAuthorNoteStrengthForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return _authorNoteStrength;
    final id = _getCharacterIdFromCard(c);
    return _groupAuthorNoteStrengths[id] ?? _authorNoteStrength;
  }

  /// Sets or clears a per-character Author's Note for the given card while in
  /// a group chat. The value is persisted via the hidden group state checkpoint.
  /// [strength] is accepted for forward compatibility (per-note strength) but
  /// currently all per-char notes use the group's authorNoteStrength for
  /// prompt formatting. Pass empty [note] to clear.
  void setAuthorNoteForGroupCharacter(
    CharacterCard c,
    String note, {
    int? strength,
  }) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(c);
    final trimmed = note.trim();

    if (trimmed.isEmpty) {
      _groupAuthorNotes.remove(id);
      _groupAuthorNoteStrengths.remove(id);
    } else {
      _groupAuthorNotes[id] = trimmed;
      // Store per-character strength if provided, otherwise fall back to group default
      final effectiveStrength = strength ?? _authorNoteStrength;
      _groupAuthorNoteStrengths[id] = effectiveStrength;
    }

    // (old checkpoint call removed in v30)
    _saveChat();
    notifyListeners();
  }

  /// Returns the system prompt (if any) stored specifically for this character
  /// *within the current group chat*. This is completely separate from the
  /// character's normal `systemPrompt` on their card (used in 1:1 chats).
  /// Returns '' if not in a group or no per-character group prompt has been set.
  /// When non-empty, this value wins over the character's normal systemPrompt
  /// for prompt construction inside this group.
  String getSystemPromptForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return '';
    final id = _getCharacterIdFromCard(c);
    return _groupCharacterSystemPrompts[id] ?? '';
  }

  /// Sets or clears a per-character system prompt override for the given
  /// character while inside a group chat. The value is persisted via the
  /// hidden group state checkpoint (no DB schema change).
  /// This affects only the current group. Pass empty [prompt] to clear.
  /// The provided prompt takes precedence over the character's normal
  /// `systemPrompt` when this character speaks in the group.
  void setSystemPromptForGroupCharacter(CharacterCard c, String prompt) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(c);
    final trimmed = prompt.trim();

    if (trimmed.isEmpty) {
      _groupCharacterSystemPrompts.remove(id);
    } else {
      _groupCharacterSystemPrompts[id] = trimmed;
    }

    // (old checkpoint call removed in v30)
    _saveChat();
    notifyListeners();
  }
}
