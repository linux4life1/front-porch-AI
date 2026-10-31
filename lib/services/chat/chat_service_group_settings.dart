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

  Map<String, double> get currentGroupRAGPriorities =>
      Map.unmodifiable(_groupCharacterRAGPriorities);

  /// RAG retrieval priority for [c] in the active group (1.0 = neutral).
  /// Card-keyed on purpose: storage uses the stable character id — the same
  /// key retrieval multiplies by (memory_service characterPriorities) — and
  /// the settings dialog only has cards. The old NAME-keyed dialog reads
  /// always missed and every character showed 1.0.
  double ragPriorityForGroupCharacter(CharacterCard c) =>
      _groupCharacterRAGPriorities[_getCharacterIdFromCard(c)] ?? 1.0;

  void setRAGPriorityForGroupCharacter(CharacterCard c, double priority) {
    if (_activeGroup == null) return;
    _groupCharacterRAGPriorities[_getCharacterIdFromCard(c)] = priority;
    notifyListeners();
  }

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

  /// Whether the active group currently uses RANDOM turn order (vs round-robin).
  bool get isGroupTurnOrderRandom =>
      _activeGroup?.turnOrder == TurnOrder.random;

  /// Whether Afterglow (arousal / the Lust bar) is on for the body the live
  /// scalars hold: Porch Life (with 18+ on) allows it, the chat's own switch
  /// is on and, in a group, the loaded member's own, read live. For one
  /// member of the group, read [afterglowRunsFor].
  bool get isGroupNsfwEnabled => _nsfwService.nsfwCooldownEnabled;

  /// Whether Afterglow runs for [member] in this chat: Porch Life (with 18+)
  /// allows it, the chat's switch is on and, in a group, the member's own.
  bool afterglowRunsFor(CharacterCard member) =>
      _storageService.realismSettings.afterglowEnabled &&
      (_activeGroup == null
          ? _nsfwService.storedNsfwCooldownEnabled
          : _groupStore.afterglowOnFor(_getCharacterIdFromCard(member)));

  /// A group member's own Afterglow switch, kept on their card in this group
  /// (unset reads on). Switching it either way settles their Lust and any
  /// recovery, as the chat's switch does. Class forwarder:
  /// [ChatService.setMemberAfterglowEnabled].
  Future<void> _setMemberAfterglowEnabledImpl(
    CharacterCard member,
    bool on,
  ) async {
    if (_activeGroup == null) return;
    if ((member.frontPorchExtensions?.afterglowEnabled ?? true) == on) return;
    member.frontPorchExtensions =
        (member.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
          afterglowEnabled: on,
        );
    final id = _getCharacterIdFromCard(member);
    _groupStore.memberForWrite(id)
      ..arousal = 0
      ..refractory = Refractory.none;
    if (_nsfwService.loadedMemberId == id) {
      _nsfwService.resetRuntimeArousalAndCooldown();
    }
    await persistGroupMemberExtensions(memberId: id);
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
      _session.groupManager?.refreshCharacters(customOrder);
    }
    _session.groupManager
        ?.resetTurnState(); // fresh pointer so the order starts at #1
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
