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

/// Approach A′ soft members: add/promote lite guests on the group roster.
/// Feelings helpers live in [group_lite.dart]; this part owns the ChatService
/// persist + entrance path so guest_flow / members stay under the line cap.
extension ChatServiceGroupLite on ChatService {
  /// Full members only — feelings / ≤4 gate. Soft stay on [_groupCharacters].
  List<CharacterCard> get fullGroupRoster =>
      fullGroupCharacters(_groupCharacters);

  /// Present soft guests on the live group roster.
  List<CharacterCard> get presentSoftGroupMembers => [
    for (final c in _groupCharacters)
      if (c.isLite) c,
  ];

  /// 1:1 guest turn **or** a soft group member speaking. Do not set
  /// `guestSpeaker` for the latter — that skip would drop Away / pick.
  bool _isLiteTurn(_GenTurn t) =>
      t.guestSpeaker != null || t.speakingCharacter.isLite;

  bool _sceneNameTaken(String name) {
    final wanted = name.trim().toLowerCase();
    return presentSceneNames(
      members: _groupCharacters,
      guests: _sceneGuest.cards,
    ).contains(wanted);
  }

  /// Host used when minting a guest from a group (no 1:1 `_activeCharacter`).
  CharacterCard? get _mintHost =>
      _activeCharacter ?? nextCharacter ?? _groupCharacters.firstOrNull;

  CharacterCard? _presentSoftMatching(CharacterCard card) {
    final id = _getCharacterIdFromCard(card);
    final name = card.name.trim().toLowerCase();
    for (final c in _groupCharacters) {
      if (!c.isLite) continue;
      if (id.isNotEmpty && _getCharacterIdFromCard(c) == id) return c;
      if (c.name.trim().toLowerCase() == name) return c;
    }
    return null;
  }

  /// Clear `tier`, persist the row, seed needs + feelings like a new full
  /// member. Already-present — no entrance. Shared by `/join --full`,
  /// `/promote <name>`, and the roster Promote control.
  Future<void> promoteGuestToFull(CharacterCard member) async {
    if (_activeGroup == null) return;
    final live = _presentSoftMatching(member) ?? member;
    if (!live.isLite) {
      _setGuestStatus('${live.name} is already a full member.');
      return;
    }
    if (_isTurnBusy) {
      _setGuestStatus(
        '⚠ Wait for the current reply to finish first.',
        isError: true,
      );
      return;
    }
    final mid = _getCharacterIdFromCard(live);
    final cleared = cloneFrontPorchTier(live.frontPorchExtensions, lite: false);
    live.frontPorchExtensions = cleared;
    if (live.dbId != null) {
      await _db.updateGroupMember(
        GroupMembersCompanion(
          id: drift.Value(live.dbId!),
          frontPorchExtensions: drift.Value(encodeMemberFrontPorch(cleared)),
        ),
      );
    }
    await _reloadGroupRoster();
    if (_needsSimEnabled && mid.isNotEmpty && _getGroupNeeds(mid).isEmpty) {
      _setGroupNeeds(mid, NeedsSimulation.baselinesFromExtensions(cleared));
    }
    if (mid.isNotEmpty) {
      _relationshipService.ensureInterCharacterRelationshipsSeeded(mid);
      for (final other in fullGroupRoster) {
        _relationshipService.ensureInterCharacterRelationshipsSeeded(
          _getCharacterIdFromCard(other),
        );
      }
    }
    await _saveChat();
    _setGuestStatus('${live.name} is now a full member.');
    notifyListeners();
  }

  /// Insert [card] as a soft member and (by default) write an organic entrance.
  Future<bool> _addLiteMemberToGroup(
    CharacterCard card, {
    bool entrance = true,
  }) async {
    final repo = _groupChatRepository;
    if (repo == null || _activeGroup == null) {
      _setGuestStatus(
        '⚠ Group support is unavailable right now.',
        isError: true,
      );
      return false;
    }
    final ok = await addCharacterToGroup(card, repo, asLite: true);
    if (!ok) return false;
    if (!entrance) return true;
    final resolved = _groupCharacters.firstWhere(
      (c) => c.name == card.name,
      orElse: () => card,
    );
    await _generateMemberEntrance(
      resolved,
      'enter the scene naturally, reacting to what is happening',
    );
    return true;
  }
}
