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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'entry_door.dart';

/// A group's live roster: a member joins (their card copied into the
/// group's private storage under a new member row), leaves (row, avatar
/// and every per-member store, collapsing to a 1:1 when one is left), and
/// the roster re-read from the member table. Members borrow their library
/// character's expression images.
class GroupRoster {
  GroupRoster(this._door, this._d);

  final EntryDoor _door;
  final EntryDeps _d;

  ChatSessionState get _session => _d.session;
  EntryServices get _s => _d.services;
  CastDoor get _cast => _s.cast();
  AppDatabase get _db => _s.db();
  GroupChat? get _activeGroup => _session.activeGroup;
  GroupRealismStore get _groupStore => _s.realism().groups;
  bool get _isTurnBusy => _s.turn().isTurnBusy;
  String _getCharacterIdFromCard(CharacterCard c) =>
      _d.shared.characterIdFor(c);

  /// The chat's stored Needs switch: a member who joins is seeded under it.
  bool get _needsSimEnabled => _s.realism().needsSimEnabled();

  /// Create a group member (decoupled model): copy the character's avatar into
  /// the group's private storage and insert a group_members row.
  /// Shared by [addCharacterToGroup] (live add) and [GroupFork.forkToGroupChat] (initial
  /// membership when forking a 1:1 chat into a group).
  ///
  /// This is the core of the fix originally contributed in PR #44 by @MisterLotto.
  Future<String> createGroupMember(
    String groupId,
    CharacterCard character, {
    bool asLite = false,
  }) async {
    final mid = const Uuid().v4();
    final avDir = Directory(
      path.join(_s.storage.groupsDir.path, groupId, 'avatars'),
    );
    await avDir.create(recursive: true);

    await _s.characters()!.duplicateCharacter(
      character,
      targetDirOverride: avDir.path,
      forcedBasename: mid,
      skipLibraryInsert: true,
    );

    await _db.insertGroupMember(
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
        worldNames: drift.Value(jsonEncode(character.allWorldNames)),
        frontPorchExtensions: drift.Value(
          encodeMemberFrontPorch(
            joiningMemberFrontPorch(
              asLite
                  ? cloneFrontPorchTier(
                      character.frontPorchExtensions,
                      lite: true,
                    )
                  : character.isLite
                  ? cloneFrontPorchTier(
                      character.frontPorchExtensions,
                      lite: false,
                    )
                  : character.frontPorchExtensions,
            ),
          ),
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
    GroupChatRepository groupRepo, {
    bool asLite = false,
  }) async {
    if (_activeGroup == null || _s.characters() == null) return false;
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
      _cast.guests.setStatus(
        '⚠ ${character.name} is already in this chat.',
        isError: true,
      );
      return false;
    }

    // Decoupled model: copy the character's avatar into the group's private
    // storage and insert a group_members row. Shared with forkToGroupChat
    // via _createGroupMember (ported from the fix originally contributed in
    // PR #44 by @MisterLotto).
    final mid = await createGroupMember(
      _activeGroup!.id,
      character,
      asLite: asLite,
    );

    await groupRepo.save(_activeGroup!);

    // Re-resolve from private members (decoupled).
    final resolved = <CharacterCard>[];
    final memberRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _s.storage.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        resolved.add(m.toCharacterCard(resolvedImagePath: p));
      } else {
        resolved.add(m.toCharacterCard(resolvedImagePath: ''));
      }
    }
    inheritGroupExpressionAvatars(resolved);
    _session.groupManager?.refreshCharacters(resolved);
    if (!asLite && _needsSimEnabled && _groupStore.needsOf(mid).isEmpty) {
      _groupStore.setNeeds(
        mid,
        NeedsSimulation.baselinesFromExtensions(character.frontPorchExtensions),
      );
    }

    // The new member starts with the switches the chat holds.
    _s.graph().seedGroupMemberSwitches();

    debugPrint(
      '[Chat] \u{2795} Added ${character.name} to group ${_activeGroup!.name}',
    );
    _d.notify();
    return true;
  }

  /// Re-resolve the group's live roster from the member table and push it to the
  /// turn manager, returning the resolved cards. Missing avatars still keep the
  /// member on the roster (same rule as [GroupEntry.setActiveGroup]). Shared by member
  /// removal (after the delete) and the deferred-exit undo (after a soft-remove,
  /// where the row still exists so the member comes straight back).
  Future<List<CharacterCard>> reloadGroupRoster() async {
    final repo = _door.groupRepository;
    if (_activeGroup == null || repo == null) return const <CharacterCard>[];
    final rows = await repo.getMembersForGroup(_activeGroup!.id);
    final resolved = <CharacterCard>[];
    for (final m in rows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _s.storage.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        resolved.add(m.toCharacterCard(resolvedImagePath: p));
      } else {
        resolved.add(m.toCharacterCard(resolvedImagePath: ''));
      }
    }
    inheritGroupExpressionAvatars(resolved);
    _session.groupManager?.refreshCharacters(resolved);
    return resolved;
  }

  /// Remove a character from the active group chat: deletes the member's row,
  /// private avatar, and ALL per-member state (realism / notes / prompts / RAG /
  /// objectives / embeddings / data-bank), then re-resolves the surviving cast.
  /// When the removal leaves exactly ONE member the group auto-collapses back
  /// into a 1:1 with that member's ORIGINAL library character (a one-character
  /// group is nonsense) — see [CastCollapse.collapseGroupToSolo].
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _s.characters() == null) return false;
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
    await _cast.roster.deleteMemberCleanup(charId, removedAvatar);
    await groupRepo.save(_activeGroup!);

    // Re-resolve the surviving members from the (now smaller) member table.
    final resolved = await reloadGroupRoster();

    debugPrint(
      '[Chat] \u{2796} Removed ${character.name} from group '
      '${_activeGroup!.name} (${resolved.length} left)',
    );

    // Persist the cleaned per-character maps to the session now, so the removed
    // member's realism/notes/etc. can't re-enter the group_realism_state blob on
    // a later save.
    await _d.sessions().save();

    // A one-character group is nonsense — collapse straight back to a 1:1 with
    // the survivor's original library character (auto, no prompt). If the collapse
    // can't proceed (origin unresolvable, or the group has other saved
    // conversations), _collapseGroupToSolo surfaces a banner and we stay a
    // one-member cast.
    if (resolved.length == 1) {
      await _cast.collapse.collapseGroupToSolo(groupRepo);
      return true;
    }

    _d.notify();
    return true;
  }

  /// The LIBRARY character this card came from. Identity first (dbId, then
  /// stableGroupId), name only when it is unique — two "Rachel"s must not
  /// share a face. Null when there is no confident match (imported-only
  /// member, or two library cards with the same name and no stamp).
  /// Used to inherit expressions and to route the in-chat Expression
  /// Images editor at the member's real library home.
  CharacterCard? originLibraryCardFor(CharacterCard member) {
    final lib = _s.characters()?.characters;
    if (lib == null) return null;
    return MemberOriginResolver.resolveForCard(member, lib);
  }

  /// Group members are single-avatar copies of LIBRARY characters (the decoupled
  /// model stores one PNG per member, no expression set). For the expression
  /// display, inherit the origin library character's expression images. No
  /// per-member storage: a character that has expressions set up in your library
  /// shows them in the group; a member with no library match keeps its single
  /// avatar. Mutates each card's `avatarImages` in place (defensive copy so the
  /// member can never mutate the shared library list).
  void inheritGroupExpressionAvatars(List<CharacterCard> members) {
    for (final m in members) {
      if (m.avatarImages != null && m.avatarImages!.isNotEmpty) continue;
      final origin = originLibraryCardFor(m);
      if (origin?.avatarImages != null && origin!.avatarImages!.isNotEmpty) {
        // The prime index belongs with the images: it names the face a
        // label with no match falls back on.
        m
          ..avatarImages = List<AvatarImage>.from(origin.avatarImages!)
          ..primeAvatarIndex = origin.primeAvatarIndex;
      }
    }
  }
}
