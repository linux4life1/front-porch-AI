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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

/// The two directions a chat's cast changes shape: a group down to one
/// member collapses back into a 1:1 with that member's library character,
/// and a 1:1 that becomes a group carries its host's state onto the host
/// member. The Realism scalars (and the chat's own Realism switch) carry
/// through [CastShellHooks.captureSurvivor] and
/// [CastShellHooks.carryHostScalars].
class CastCollapse {
  CastCollapse(this._door, this._d);

  final CastDoor _door;
  final CastDeps _d;

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;

  /// Collapse a group that dropped to a SINGLE member back into a 1:1 with
  /// that member's ORIGINAL library character. Re-homes the CURRENT session
  /// in place (all history kept), carries the survivor's realism back into
  /// the 1:1 (the inverse of [carryHostStateIntoForkedGroup]), then
  /// dissolves the now-empty group.
  ///
  /// If the survivor's origin can't be resolved ([MemberOriginResolver]) it
  /// stays a one-member cast rather than guessing. True if it collapsed.
  Future<bool> collapseGroupToSolo(GroupChatRepository groupRepo) async {
    final group = _session.activeGroup;
    final sessionId = _session.currentSessionId;
    if (group == null || sessionId == null) return false;
    if (_session.groupCharacters.length != 1) return false;

    final sole = _session.groupCharacters.first;
    final soleId = _d.characterIdFor(sole); // member instance id (mid)
    final soleKey = _door.memory.keyFor(sole);

    // Resolve the survivor back to its origin library character. The origin
    // link lives on the member ROW, not the loaded card.
    final rows = await groupRepo.getMembersForGroup(group.id);
    String? originStamp;
    for (final m in rows) {
      if (m.id == soleId) {
        originStamp = m.originStableId;
        break;
      }
    }
    final origin = MemberOriginResolver.resolve(
      stampedOriginStableId: originStamp,
      memberName: sole.name,
      libraryCharacters: _d.characters()?.characters ?? const <CharacterCard>[],
    );
    if (origin == null || origin.dbId == null) {
      debugPrint('[Cast] collapse skipped: ${sole.name} origin unresolvable');
      _door.guests.setStatus(
        '⚠ Couldn’t match ${sole.name} back to a library character, so this '
        'stays a group. (Re-import or rename it to match the original.)',
        isError: true,
      );
      _d.notify();
      return false;
    }

    // Only auto-dissolve when THIS is the group's only session: dissolving
    // hard-deletes every session of the group and its messages.
    final groupSessions = await _d.db.getSessionsForGroup(group.id);
    if (groupSessions.length > 1) {
      debugPrint(
        '[Cast] collapse skipped: group "${group.name}" has '
        '${groupSessions.length} sessions — not auto-dissolving (would lose history)',
      );
      _door.guests.setStatus(
        '⚠ This group has other saved conversations, so it can’t auto-collapse '
        'to a 1:1. Delete the other group chats first.',
        isError: true,
      );
      _d.notify();
      return false;
    }

    // 1) While still in group mode, capture the survivor's full state to
    //    carry back to the 1:1. originId is the id the 1:1 keys by.
    final originId = _d.characterIdFor(origin);
    final restoreSurvivor = _d.graph().carries.captureSurvivor(soleId);
    // Undistilled legacy evolved text (pre-rings growth) moves from the
    // group JSON maps to the 1:1 columns after re-home.
    String soleLegacyPers = '';
    String soleLegacyScen = '';
    try {
      final sessRow = await _d.db.getSessionById(sessionId);
      if (sessRow != null) {
        soleLegacyPers =
            _h.parseJsonMap(sessRow.groupEvolvedPersonalities)[soleId] ?? '';
        soleLegacyScen =
            _h.parseJsonMap(sessRow.groupEvolvedScenarios)[soleId] ?? '';
      }
    } catch (_) {}

    // 2) Re-home the session to a 1:1 owned by the library character. Bump
    //    createdAt so the most-recent-session load lands on exactly this
    //    session; clear group_realism_state so the 1:1 load skips it.
    final reHomed = await _d.db.patchSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        groupId: const drift.Value(null),
        characterId: drift.Value(origin.dbId),
        groupRealismState: const drift.Value('{}'),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    if (!reHomed) {
      // No row: abort BEFORE dissolving, so the group is never deleted
      // while its session is still group-homed.
      debugPrint(
        '[Cast] collapse aborted: re-home patchSession matched no row',
      );
      _d.notify();
      return false;
    }

    // 3) Dissolve the now-empty group. The re-homed session's groupId is
    //    null, so the repo's by-groupId session sweep cannot touch it.
    await groupRepo.delete(group.id);

    // Re-key the survivor's group-era objectives, rings, memory and diary
    // to the origin id, so they survive the collapse.
    try {
      await _d.db.reassignObjectives(soleId, originId, chatId: sessionId);
      await _d.db.reassignGrowthRings(soleId, originId, sessionId: sessionId);
      // The survivor's own windows (their member key), and the old shared
      // pool of a chat from before per-member memory, become the 1:1's.
      for (final from in {soleKey, ...legacyGroupMemoryBuckets(group.id)}) {
        if (from != originId) {
          await _d.db.reassignEmbeddings(from, originId, chatId: sessionId);
        }
      }
      // Journal cards sit under the MEMBER instance id; the 1:1 reads them
      // under originId.
      await _door.roster.moveJournalCards(sessionId, soleId, originId);
      await _d.db.deleteDataBankEntriesForCharacter(soleId);
    } catch (e) {
      debugPrint('[Cast] state re-key (non-fatal): $e');
    }

    // 4) Re-enter as a 1:1 on the re-homed session; force the exact session
    //    if another session of this character is newer.
    await _h.setActiveCharacter(origin);
    if (_session.currentSessionId != sessionId) {
      await _h.loadSession(sessionId);
    }

    // 5) Restore the carried state into the 1:1 (the open reset it).
    restoreSurvivor();

    // Rings were re-keyed in place above. Move any undistilled legacy
    // evolved text to the 1:1 columns.
    if (soleLegacyPers.isNotEmpty || soleLegacyScen.isNotEmpty) {
      await _d.db.patchSession(
        SessionsCompanion(
          id: drift.Value(sessionId),
          evolvedPersonality: drift.Value(soleLegacyPers),
          evolvedScenario: drift.Value(soleLegacyScen),
          groupEvolvedPersonalities: const drift.Value('{}'),
          groupEvolvedScenarios: const drift.Value('{}'),
        ),
      );
    }
    await _d.growthDesk().refreshCache();
    await _d.saveChat();
    _d.notify();
    debugPrint(
      '[Cast] collapsed group "${group.name}" → 1:1 with ${origin.name}',
    );
    return true;
  }

  /// Carry captured 1:1 [state] onto the host member (1:1 to group,
  /// lossless). Realism values only if realism was on; flags, author note,
  /// pockets, growth, objectives, journal and RAG copy regardless. No-op if
  /// the host member cannot be resolved. [originalCharId] / [hostSessionId]
  /// are the 1:1 keys.
  Future<void> carryHostStateIntoForkedGroup(
    String hostName,
    String originalCharId,
    String? hostSessionId,
    Map<String, dynamic> state,
  ) async {
    if (_session.activeGroup == null) return;
    CharacterCard? hostMember;
    for (final c in _session.groupCharacters) {
      if (c.name == hostName) {
        hostMember = c;
        break;
      }
    }
    if (hostMember == null) return; // host member not found: don't mis-key
    final hostId = _d.characterIdFor(hostMember);
    _d.graph().carries.carryHostScalars(hostId, state);

    // COPY the host's objectives, memory and growth onto the new group (the
    // original 1:1 stays the revert snapshot; collapse re-keys instead).
    final sessionId = _session.currentSessionId;
    if (hostSessionId != null && sessionId != null) {
      await _d.growthStore().carryOwnerGrowth(
        fromSessionId: hostSessionId,
        fromCharId: originalCharId,
        toSessionId: sessionId,
        toCharId: hostId,
        fromIsGroup: false,
        toIsGroup: true,
      );
      await _d.growthDesk().refreshCache();
      await _copyObjectives(originalCharId, hostSessionId, hostId);
      // Journal cards: copy, not move. The fork copies every message and
      // the recap cursor, so a skipped diary could never rebuild.
      try {
        for (final card in await _d.journal().cardsFor(
          hostSessionId,
          originalCharId,
        )) {
          await _d.db.insertJournalCard(
            JournalMemoriesCompanion(
              sessionId: drift.Value(_session.currentSessionId!),
              characterId: drift.Value(hostId),
              content: drift.Value(card.content),
              category: drift.Value(card.category),
              emotionLabel: drift.Value(card.emotionLabel),
              emotionIntensity: drift.Value(card.emotionIntensity),
              originalEmotionLabel: drift.Value(card.originalEmotionLabel),
              sourceMessageIds: drift.Value(card.sourceMessageIds),
              metadata: drift.Value(card.metadata),
              heat: drift.Value(card.heat),
              pinned: drift.Value(card.pinned),
              accessCount: drift.Value(card.accessCount),
              embedding: drift.Value(card.embedding),
              dimensions: drift.Value(card.dimensions),
              lastAccessedAt: drift.Value(card.lastAccessedAt),
            ),
          );
        }
      } catch (e) {
        debugPrint('[Cast] host journal carry-on-fork (non-fatal): $e');
      }
      // RAG memory goes to the host member's own memory in the new chat: the
      // others were not there for the 1:1, so only the host recalls it.
      try {
        await _d.db.copyEmbeddingsForSession(
          originalCharId,
          hostSessionId,
          toCharacterId: _door.memory.keyFor(hostMember),
          toSessionId: _session.currentSessionId!,
        );
      } catch (e) {
        debugPrint('[Cast] host RAG carry-on-fork (non-fatal): $e');
      }
    }

    await _d.saveChat();
    _d.notify();
  }

  /// The host's 1:1 objectives, onto the host MEMBER in the new session.
  Future<void> _copyObjectives(
    String originalCharId,
    String hostSessionId,
    String hostId,
  ) async {
    final origObjs = await _d.db.getObjectivesForCharacter(
      originalCharId,
      chatId: hostSessionId,
    );
    for (final o in origObjs) {
      await _d.db.insertObjective(
        ObjectivesCompanion.insert(
          id: const Uuid().v4(),
          characterId: hostId,
          objective: o.objective,
          chatId: drift.Value(_session.currentSessionId),
          tasks: drift.Value(o.tasks),
          active: drift.Value(o.active),
          isPrimary: drift.Value(o.isPrimary),
          checkFrequency: drift.Value(o.checkFrequency),
          injectionDepth: drift.Value(o.injectionDepth),
          // The rest of the goal comes too: who it is from, where it
          // stands, which ambition it serves, and when it began and ended.
          servedAmbition: drift.Value(o.servedAmbition),
          origin: drift.Value(objectiveOrigin(o)),
          status: drift.Value(o.status),
          createdAt: drift.Value(o.createdAt),
          endedAt: drift.Value(o.endedAt),
        ),
      );
    }
  }
}
