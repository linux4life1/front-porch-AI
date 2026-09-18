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

/// Live add / remove / create-member. 1:1→group fork stays on
/// [ChatServiceGroupMembership].
extension ChatServiceGroupMembers on ChatService {
  /// Create a group member (decoupled model): copy the character's avatar into
  /// the group's private storage and insert a group_members row.
  /// Shared by [addCharacterToGroup] (live add) and [forkToGroupChat] (initial
  /// membership when forking a 1:1 chat into a group).
  ///
  /// This is the core of the fix originally contributed in PR #44 by @MisterLotto.
  Future<String> _createGroupMember(
    String groupId,
    CharacterCard character,
  ) async {
    final mid = const Uuid().v4();
    final avDir = Directory(
      path.join(_storageService.groupsDir.path, groupId, 'avatars'),
    );
    await avDir.create(recursive: true);

    await _characterRepository!.duplicateCharacter(
      character,
      targetDirOverride: avDir.path,
      forcedBasename: mid,
      skipLibraryInsert: true,
    );

    final db = await AppDatabase.instance();
    await db.insertGroupMember(
      GroupMembersCompanion(
        id: drift.Value(mid),
        groupId: drift.Value(groupId),
        name: drift.Value(character.name),
        description: drift.Value(character.description),
        personality: drift.Value(character.personality),
        scenario: drift.Value(character.scenario),
        firstMessage: drift.Value(character.firstMessage),
        mesExample: drift.Value(character.mesExample),
        systemPrompt: drift.Value(character.systemPrompt),
        postHistoryInstructions: drift.Value(character.postHistoryInstructions),
        alternateGreetings: drift.Value(
          jsonEncode(character.alternateGreetings),
        ),
        tags: drift.Value(jsonEncode(character.tags)),
        avatarFilename: drift.Value('$mid.png'),
        ttsVoice: drift.Value(character.ttsVoice),
        lorebook: drift.Value(
          character.lorebook != null
              ? jsonEncode(character.lorebook!.toJson())
              : null,
        ),
        worldNames: drift.Value(jsonEncode(character.worldNames)),
        frontPorchExtensions: drift.Value(
          character.frontPorchExtensions != null
              ? jsonEncode(character.frontPorchExtensions!.toJson())
              : null,
        ),
        rawExtensions: drift.Value(
          character.rawExtensions != null
              ? jsonEncode(character.rawExtensions!)
              : null,
        ),
        // Provenance: stamp which library character this member was copied from
        // so a chat can later collapse back to a 1:1 with the original (no orphans).
        memberState: drift.Value(
          GroupMember.encodeProvenance(
            originStableId: character.stableGroupId,
            originLibraryDbId: character.dbId,
          ),
        ),
      ),
    );
    return mid;
  }

  /// Add a character to the currently active group chat.
  Future<bool> addCharacterToGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isTurnBusy) return false;

    // D5 — one instance per library character per chat. Refuse to add a
    // character already present (the host or an existing member), matched by
    // stable LIBRARY identity (Phase 0 originStableId), with a name fallback for
    // legacy members that predate provenance stamping.
    final incomingId = _getCharacterIdFromCard(character);
    final incomingName = character.name.trim().toLowerCase();
    final existingMembers = await groupRepo.getMembersForGroup(
      _activeGroup!.id,
    );
    final alreadyPresent = existingMembers.any((m) {
      final origin = m.originStableId;
      if (origin != null && origin == incomingId) return true;
      return m.name.trim().toLowerCase() == incomingName;
    });
    if (alreadyPresent) {
      _setGuestStatus(
        '⚠ ${character.name} is already in this chat.',
        isError: true,
      );
      return false;
    }

    // Decoupled model: copy the character's avatar into the group's private
    // storage and insert a group_members row. Shared with forkToGroupChat
    // via _createGroupMember (ported from the fix originally contributed in
    // PR #44 by @MisterLotto).
    final mid = await _createGroupMember(_activeGroup!.id, character);

    await groupRepo.save(_activeGroup!);

    // Re-resolve from private members (decoupled).
    final resolved = <CharacterCard>[];
    final memberRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      }
    }
    _inheritGroupExpressionAvatars(resolved);
    _groupManager?.refreshCharacters(resolved);
    if (_needsSimEnabled && _getGroupNeeds(mid).isEmpty) {
      _setGroupNeeds(
        mid,
        NeedsSimulation.baselinesFromExtensions(character.frontPorchExtensions),
      );
    }

    debugPrint(
      '[ChatService] \u{2795} Added ${character.name} to group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Re-resolve the group's live roster from the member table and push it to the
  /// turn manager, returning the resolved cards. Members whose private avatar is
  /// missing are skipped (same rule as the initial group load). Shared by member
  /// removal (after the delete) and the deferred-exit undo (after a soft-remove,
  /// where the row still exists so the member comes straight back).
  Future<List<CharacterCard>> _reloadGroupRoster() async {
    final repo = _groupChatRepository;
    if (_activeGroup == null || repo == null) return const <CharacterCard>[];
    final rows = await repo.getMembersForGroup(_activeGroup!.id);
    final resolved = <CharacterCard>[];
    for (final m in rows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      }
    }
    _inheritGroupExpressionAvatars(resolved);
    _groupManager?.refreshCharacters(resolved);
    return resolved;
  }

  /// Remove a character from the active group chat: deletes the member's row,
  /// private avatar, and ALL per-member state (realism / notes / prompts / RAG /
  /// objectives / embeddings / data-bank), then re-resolves the surviving cast.
  /// When the removal leaves exactly ONE member the group auto-collapses back
  /// into a 1:1 with that member's ORIGINAL library character (a one-character
  /// group is nonsense) — see [_collapseGroupToSolo].
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isTurnBusy) return false;

    final charId = _getCharacterIdFromCard(
      character,
    ); // member instance id (mid)

    // Find the member's avatar filename before the row is deleted.
    final beforeRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    String? removedAvatar;
    for (final m in beforeRows) {
      if (m.id == charId) {
        removedAvatar = m.avatarFilename;
        break;
      }
    }

    // Delete the row + avatar + per-member DB state + in-memory maps.
    await _deleteMemberCleanup(charId, removedAvatar);
    await groupRepo.save(_activeGroup!);

    // Re-resolve the surviving members from the (now smaller) member table.
    final resolved = await _reloadGroupRoster();

    debugPrint(
      '[ChatService] \u{2796} Removed ${character.name} from group '
      '${_activeGroup!.name} (${resolved.length} left)',
    );

    // Persist the cleaned per-character maps to the session now, so the removed
    // member's realism/notes/etc. can't re-enter the group_realism_state blob on
    // a later save.
    await _saveChat();

    // A one-character group is nonsense — collapse straight back to a 1:1 with
    // the survivor's original library character (auto, no prompt). If the collapse
    // can't proceed (origin unresolvable, or the group has other saved
    // conversations), _collapseGroupToSolo surfaces a banner and we stay a
    // one-member cast.
    if (resolved.length == 1) {
      await _collapseGroupToSolo(groupRepo);
      return true;
    }

    notifyListeners();
    return true;
  }
}
