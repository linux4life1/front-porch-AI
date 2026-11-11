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

import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

/// Why [CastController.canRemoveCastMember] refused a member's exit.
const kDirectorCastFloorNote =
    'While you direct, the scene keeps at least two characters. Step back '
    'in with /director off first.';

/// "One chat, a cast that changes": the group roster's full and soft
/// members, a member's narrated `/exit` with its deferred removal and undo,
/// per-member cleanup, and soft members joining and being promoted. The
/// collapse to a 1:1 and the 1:1 to group host carry are [CastCollapse].
class CastController {
  CastController(this._door, this._d);

  final CastDoor _door;
  final CastDeps _d;

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();
  SceneGuestState get _state => _door.guests.state;
  List<CharacterCard> get _cast => _session.groupCharacters;

  /// Full members only (feelings, the four-member gate). Soft members stay
  /// on the group roster.
  List<CharacterCard> get fullGroupRoster => fullGroupCharacters(_cast);

  /// Soft on the card **or** a same-id/name roster guest: a speaking copy
  /// that lost `tier` while the roster stayed GUEST leaked Realism once.
  bool speakerIsSoft(CharacterCard speaker) =>
      speaker.isLite || presentSoftMatching(speaker) != null;

  /// The chat's STORED Needs switch: a promote seeds state with it
  /// (test/hygiene/needs_gate_ratchet_test.dart allows this file).
  bool get _needsSimEnabled => _d.realism().needsSimEnabled();

  /// A soft member who becomes full gets a full member's bars (only when
  /// the chat keeps Needs state and they have none yet).
  void _seedPromotedNeeds(String mid, FrontPorchExtensions? cleared) {
    final groups = _d.realism().groups;
    if (_needsSimEnabled && mid.isNotEmpty && groups.needsOf(mid).isEmpty) {
      groups.setNeeds(mid, NeedsSimulation.baselinesFromExtensions(cleared));
    }
  }

  bool sceneNameTaken(String name) {
    final wanted = name.trim().toLowerCase();
    return presentSceneNames(
      members: _cast,
      guests: _state.cards,
    ).contains(wanted);
  }

  CharacterCard? presentSoftMatching(CharacterCard card) {
    final id = _d.characterIdFor(card);
    final name = card.name.trim().toLowerCase();
    for (final c in _cast) {
      if (!c.isLite) continue;
      if (id.isNotEmpty && _d.characterIdFor(c) == id) return c;
      if (c.name.trim().toLowerCase() == name) return c;
    }
    return null;
  }

  /// Whether a member may leave now. While the user directs, the scene keeps
  /// two characters: one left would turn the group back into a 1:1 and end
  /// Director Mode under the next note.
  bool get canRemoveCastMember => _cast.length > (_h.directing() ? 2 : 1);

  /// `/exit <name>` for a FULL group member, with a narrated departure and a
  /// true UNDO (deferred deletion):
  ///   1. The leaving member narrates their own brief goodbye.
  ///   2. They drop out of the LIVE roster, but their row, realism,
  ///      evolution, quests and memory stay intact, and an UNDO is armed.
  ///   3. The destructive removal waits for [commitPendingMemberExit], which
  ///      `sendMessage` runs when the user continues, so the undo restores
  ///      them exactly. An exit that leaves one character commits at once:
  ///      the group turns back into a 1:1 there and then, with no UNDO.
  /// True once the goodbye is staged and the exit is pending.
  Future<bool> exitGroupMember(
    CharacterCard member,
    GroupChatRepository groupRepo,
  ) async {
    if (_session.activeGroup == null || _turn.isTurnBusy) return false;
    // The UNDO only applies to the most recent `/exit`, so a second exit
    // commits the first. That may have collapsed the group or removed this
    // member, so re-check before going on.
    await commitPendingMemberExit();
    if (_session.activeGroup == null) return false;
    if (!canRemoveCastMember) {
      _door.guests.setStatus(kDirectorCastFloorNote, isError: true);
      return false;
    }
    final stillMember = _cast.any(
      (c) => _d.characterIdFor(c) == _d.characterIdFor(member),
    );
    if (!stillMember) return false;
    // 1. The departure in the member's own voice, through the one-shot
    //    hidden stage direction the entrance flow uses.
    _session.groupManager?.setNextSpeaker(member);
    _door.entranceDirective =
        'Stage direction (hidden — do NOT quote or copy this text into the '
        'reply): ${member.name} is leaving the conversation now. Write '
        '${member.name}\'s short, in-character goodbye / exit, in their own '
        'voice and words.';
    final before = _session.messages.length;
    try {
      await _turn.generate(GenerationMode.normal);
    } catch (e) {
      debugPrint('[Cast] exit narration for ${member.name} failed: $e');
      _door.entranceDirective = null; // don't leak into a later turn
    }
    await _door.stage.dropSilentStagedTurn(before);
    // 2. Soft-remove from the live roster only: nothing on disk is touched,
    //    so the removal stays reversible until the user continues.
    final memberId = _d.characterIdFor(member);
    final remaining = _cast
        .where((c) => _d.characterIdFor(c) != memberId)
        .toList();
    if (remaining.length < 2) {
      _door.guests.clearExitUndo();
      await _turn.waitForTurnToSettle();
      if (await _h.removeFromGroup(member, groupRepo)) return true;
      // Still busy: the next send commits it, as for any exit.
    }
    _session.groupManager?.refreshCharacters(remaining);
    _state.pendingMemberExit = member;
    // 3. Arm the UNDO; the goodbye turn is what undo deletes (its realism
    //    rollback included). No lite exitUndoGuest marker, so the undo takes
    //    the group branch.
    _state.exitUndoMessage =
        (_session.messages.isNotEmpty &&
            !_session.messages.last.isUser &&
            _session.messages.last.sender != 'System')
        ? _session.messages.last
        : null;
    _state.exitUndoOfferName = member.name;
    _state.exitUndoUserStep = false; // UNDO now means this exit
    await _d.saveChat();
    _d.notify();
    return true;
  }

  /// Commit a deferred full-member `/exit`: run the real removal (and any
  /// collapse to a 1:1) now the undo window has closed. No-op when nothing
  /// is pending.
  Future<void> commitPendingMemberExit() async {
    final member = _state.pendingMemberExit;
    _state.pendingMemberExit = null;
    if (member == null) return;
    final repo = _d.groupRepository();
    if (repo == null || _session.activeGroup == null) return;
    await _h.removeFromGroup(member, repo);
  }

  /// Delete every trace of a removed group member so nothing is orphaned:
  /// the row, the private avatar, the per-member persisted state
  /// (objectives, embeddings, data bank, all keyed by the member's UNIQUE
  /// instance id, so scoped deletes are safe), and the per-character maps.
  Future<void> deleteMemberCleanup(
    String charId,
    String? avatarFilename,
  ) async {
    final groupId = _session.activeGroup?.id;
    await _d.db.deleteGroupMember(charId);
    if (groupId != null && avatarFilename != null) {
      try {
        final f = File(
          path.join(
            _d.storage.groupsDir.path,
            groupId,
            'avatars',
            avatarFilename,
          ),
        );
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[Cast] avatar delete failed (non-fatal): $e');
      }
    }
    // charId is the member's unique instance UUID, so these never touch
    // another character's rows.
    await _d.db.deleteObjectivesForCharacter(charId);
    await _d.db.deleteEmbeddingsForCharacter(charId);
    await _d.db.deleteDataBankEntriesForCharacter(charId);
    _h.forgetMember(charId);
    _d.objectives().groupObjectives.remove(charId);
    // A hard-removed member leaves no growth residue, and their journal
    // cards (keyed by this instance id) would never be read again.
    if (_session.currentSessionId != null) {
      await _d.growthStore().deleteAllFor(_session.currentSessionId!, charId);
      await moveJournalCards(_session.currentSessionId!, charId, null);
      await _d.growthDesk().refreshCache();
    }
  }

  /// Move one owner's journal cards inside a chat: re-key them to
  /// [toCharacterId] (cast collapse: the diary follows its owner), or DELETE
  /// them when that is null (hard member removal). Row by row on purpose: a
  /// per-owner diary is capped at a few dozen cards.
  Future<void> moveJournalCards(
    String sessionId,
    String fromCharacterId,
    String? toCharacterId,
  ) async {
    final cards = await _d.journal().cardsFor(sessionId, fromCharacterId);
    for (final card in cards) {
      if (toCharacterId == null) {
        await _d.db.deleteJournalCard(card.id);
      } else {
        await _d.db.updateJournalCard(
          card.id,
          JournalMemoriesCompanion(
            characterId: drift.Value(toCharacterId),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );
      }
    }
  }

  /// Clear `tier`, persist the row, seed needs and feelings like a new full
  /// member. Already present, so no entrance. Shared by `/join --full`,
  /// `/promote <name>` and the roster Promote control.
  Future<void> promoteGuestToFull(CharacterCard member) async {
    if (_session.activeGroup == null) return;
    final live = presentSoftMatching(member) ?? member;
    if (!live.isLite) {
      _door.guests.setStatus('${live.name} is already a full member.');
      return;
    }
    if (_turn.isTurnBusy) {
      _door.guests.setStatus(
        '⚠ Wait for the current reply to finish first.',
        isError: true,
      );
      return;
    }
    final mid = _d.characterIdFor(live);
    final cleared = cloneFrontPorchTier(live.frontPorchExtensions, lite: false);
    live.frontPorchExtensions = cleared;
    if (live.dbId != null) {
      await _d.db.updateGroupMember(
        GroupMembersCompanion(
          id: drift.Value(live.dbId!),
          frontPorchExtensions: drift.Value(encodeMemberFrontPorch(cleared)),
        ),
      );
    }
    await _h.reloadGroupRoster();
    _seedPromotedNeeds(mid, cleared);
    // A promoted guest enters with the switches the chat held, as a member
    // joining does: later edits to a default never reach this chat.
    _d.graph().seedGroupMemberSwitches();
    if (mid.isNotEmpty) {
      final rel = _d.realism().relationship();
      rel.ensureInterCharacterRelationshipsSeeded(mid);
      for (final other in fullGroupRoster) {
        rel.ensureInterCharacterRelationshipsSeeded(_d.characterIdFor(other));
      }
    }
    await _d.saveChat();
    _door.guests.setStatus('${live.name} is now a full member.');
    _d.notify();
  }

  /// Insert [card] as a soft member and (by default) write an organic
  /// entrance.
  Future<bool> addLiteMemberToGroup(
    CharacterCard card, {
    bool entrance = true,
  }) async {
    final repo = _d.groupRepository();
    if (repo == null || _session.activeGroup == null) {
      _door.guests.setStatus(
        '⚠ Group support is unavailable right now.',
        isError: true,
      );
      return false;
    }
    final ok = await _h.addToGroup(card, repo, asLite: true);
    if (!ok) return false;
    if (!entrance) return true;
    final resolved = _cast.firstWhere(
      (c) => c.name == card.name,
      orElse: () => card,
    );
    await _door.joins.generateMemberEntrance(
      resolved,
      'enter the scene naturally, reacting to what is happening',
    );
    return true;
  }
}
