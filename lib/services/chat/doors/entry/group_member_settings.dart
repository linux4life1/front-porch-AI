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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';

import 'entry_door.dart';

/// A group member's settings in this chat: the RAG knobs, their Author's
/// Note and system prompt (the session store's [GroupSessionConfig], saved
/// in the session blob), their own Afterglow switch (on their member card)
/// and the group's turn order.
class GroupMemberSettings {
  GroupMemberSettings(this._door, this._d);

  final EntryDoor _door;
  final EntryDeps _d;

  ChatSessionState get _session => _d.session;
  EntryServices get _s => _d.services;
  SessionStore get _store => _d.sessions();
  GroupSessionConfig get _group => _store.groupConfig;
  GroupChat? get _activeGroup => _session.activeGroup;
  RealismScope get _scope => _s.realism();
  GroupRealismStore get _groupStore => _scope.groups;
  NsfwService get _nsfwService => _scope.nsfw();
  String _getCharacterIdFromCard(CharacterCard c) =>
      _d.shared.characterIdFor(c);

  // ── Group RAG / Memory Settings (stored in checkpoint) ───────────────────
  bool get groupRagEnabled => _group.ragEnabled;

  int get groupRetrievalCount => _group.retrievalCount;

  double get groupMemoryBudgetPercent => _group.memoryBudgetPercent;

  Map<String, double> get currentGroupRAGPriorities =>
      Map.unmodifiable(_group.characterRAGPriorities);

  /// RAG retrieval priority for [c] in the active group (1.0 = neutral).
  /// Card-keyed on purpose: storage uses the stable character id — the same
  /// key retrieval multiplies by (memory_service characterPriorities) — and
  /// the settings dialog only has cards. The old NAME-keyed dialog reads
  /// always missed and every character showed 1.0.
  double ragPriorityForGroupCharacter(CharacterCard c) =>
      _group.characterRAGPriorities[_getCharacterIdFromCard(c)] ?? 1.0;

  void setRAGPriorityForGroupCharacter(CharacterCard c, double priority) {
    if (_activeGroup == null) return;
    _group.characterRAGPriorities[_getCharacterIdFromCard(c)] = priority;
    _d.notify();
  }

  void setGroupRAGEnabled(bool value) {
    if (_activeGroup == null) return;
    _group.ragEnabled = value;
    // (old checkpoint call removed in v30)
    _d.notify();
  }

  void setGroupRetrievalCount(int value) {
    if (_activeGroup == null) return;
    _group.retrievalCount = value;
    // (old checkpoint call removed in v30)
    _d.notify();
  }

  void setGroupMemoryBudgetPercent(double value) {
    if (_activeGroup == null) return;
    _group.memoryBudgetPercent = value;
    // (old checkpoint call removed in v30)
    _d.notify();
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
      _s.storage.realismSettings.afterglowEnabled &&
      (_activeGroup == null
          ? _nsfwService.storedNsfwCooldownEnabled
          : _groupStore.afterglowOnFor(_getCharacterIdFromCard(member)));

  /// A group member's own Afterglow switch, kept on their card in this group
  /// (unset reads on). Off hides their Lust and any recovery and holds them
  /// where they are; on shows them again, unchanged, as the chat's switch
  /// does. Nothing of theirs, stored or live, is zeroed, and the rest of the
  /// cast is untouched. The service keeps a one-line class forwarder of the
  /// same name, which the golden fake overrides.
  Future<void> setMemberAfterglowEnabled(CharacterCard member, bool on) async {
    if (_activeGroup == null) return;
    if ((member.frontPorchExtensions?.afterglowEnabled ?? true) == on) return;
    member.frontPorchExtensions =
        (member.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
          afterglowEnabled: on,
        );
    await _s.controls().persistGroupMemberExtensions(
      memberId: _getCharacterIdFromCard(member),
    );
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
    await _door.groupRepository?.save(group);
    await _store.save();
    _d.notify();
  }

  /// Returns the Author's Note text (if any) stored specifically for this
  /// character within the current *group* chat. Uses the stable char ID.
  /// Returns '' if not in group mode or no per-character note has been set.
  /// (The group's authorNoteStrength is used for formatting during injection.)
  String getAuthorNoteForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return '';
    final id = _getCharacterIdFromCard(c);
    return _group.authorNotes[id] ?? '';
  }

  /// Returns the strength (1-10) for this character's Author's Note.
  /// Falls back to the group's current authorNoteStrength if no per-character
  /// strength has been explicitly set.
  int getAuthorNoteStrengthForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return _store.authorNoteStrength;
    final id = _getCharacterIdFromCard(c);
    return _group.authorNoteStrengths[id] ?? _store.authorNoteStrength;
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
      _group.authorNotes.remove(id);
      _group.authorNoteStrengths.remove(id);
    } else {
      _group.authorNotes[id] = trimmed;
      // Store per-character strength if provided, otherwise fall back to group default
      final effectiveStrength = strength ?? _store.authorNoteStrength;
      _group.authorNoteStrengths[id] = effectiveStrength;
    }

    // (old checkpoint call removed in v30)
    _store.save();
    _d.notify();
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
    return _group.characterSystemPrompts[id] ?? '';
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
      _group.characterSystemPrompts.remove(id);
    } else {
      _group.characterSystemPrompts[id] = trimmed;
    }

    // (old checkpoint call removed in v30)
    _store.save();
    _d.notify();
  }
}
