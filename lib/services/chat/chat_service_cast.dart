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

/// "One chat, a cast that changes" — cast-shrinking operations (Phase 3):
/// per-member cleanup on removal, and the automatic collapse of a group back to
/// a 1:1 with the original library character once only one member remains. Kept
/// out of the god file and the membership leaf to respect the 500-line cap.
extension ChatServiceCast on ChatService {
  /// `/exit <name>` for a FULL group member, with a Lite-NPC-style narrated
  /// departure AND a true UNDO (deferred-deletion):
  ///   1. The leaving member narrates their own brief goodbye (no "poof").
  ///   2. They drop out of the LIVE roster, but their DB row, realism, evolution,
  ///      quests and memory are left fully intact, and an UNDO offer is armed.
  ///   3. The destructive removal (and any auto-collapse to a 1:1) is deferred to
  ///      [_commitPendingMemberExit], which fires from `sendMessage` the moment the
  ///      user continues — so [undoLastExit] in the meantime restores them exactly.
  /// Unlike a Lite guest (never deleted, so undo is trivial), a full member is a
  /// real row; deferring the delete is what makes the undo lossless. Returns true
  /// once the goodbye is staged and the exit is pending.
  Future<bool> exitGroupMember(
    CharacterCard member,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _isGenerating) return false;
    // Finalize any prior pending exit before starting a new one — the UNDO only
    // ever applies to the most recent `/exit`, so a second exit commits the
    // first. That commit may have collapsed the group or removed this member, so
    // re-check before proceeding (a no-op in the normal single-exit case).
    await _commitPendingMemberExit();
    if (_activeGroup == null) return false;
    final stillMember = _groupCharacters.any(
      (c) => _getCharacterIdFromCard(c) == _getCharacterIdFromCard(member),
    );
    if (!stillMember) return false;
    // 1. Narrate the departure in the member's own voice, reusing the one-shot
    //    hidden stage direction the entrance flow uses (injected for the next
    //    speaker, then cleared after that turn).
    _groupManager?.setNextSpeaker(member);
    _entranceDirective =
        'Stage direction (hidden — do NOT quote or copy this text into the '
        'reply): ${member.name} is leaving the conversation now. Write '
        '${member.name}\'s short, in-character goodbye / exit, in their own '
        'voice and words.';
    try {
      await _generateResponse(GenerationMode.normal);
    } catch (e) {
      debugPrint('[Cast] exit narration for ${member.name} failed: $e');
      _entranceDirective = null; // don't leak into a later turn
    }
    // 2. Soft-remove from the live roster only — nothing on disk is touched, so
    //    the removal stays fully reversible until the user continues.
    final memberId = _getCharacterIdFromCard(member);
    final remaining = _groupCharacters
        .where((c) => _getCharacterIdFromCard(c) != memberId)
        .toList();
    _groupManager?.refreshCharacters(remaining);
    _pendingMemberExit = member;
    // 3. Arm the UNDO snackbar; the just-generated goodbye turn is what undo
    //    deletes (its realism rollback included). Mirrors armSceneGuestExitUndo
    //    but without the lite `_exitUndoGuest` marker so undoLastExit takes the
    //    group branch.
    _exitUndoMessage =
        (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.sender != 'System')
        ? _messages.last
        : null;
    _exitUndoOfferName = member.name;
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// Commit a deferred full-member `/exit`: run the real removal (and any
  /// collapse to a 1:1) now that the undo window has closed. No-op when nothing
  /// is pending. The goodbye turn was already narrated at exit time, so this only
  /// does the destructive half via the shared removal path.
  Future<void> _commitPendingMemberExit() async {
    final member = _pendingMemberExit;
    _pendingMemberExit = null;
    if (member == null) return;
    final repo = _groupChatRepository;
    if (repo == null || _activeGroup == null) return;
    await removeCharacterFromGroup(member, repo);
  }

  /// Delete every trace of a removed group member so nothing is orphaned: the
  /// DB row, the private avatar file, the per-member persisted state (objectives
  /// / embeddings / data-bank — all keyed by the member's UNIQUE instance id, so
  /// scoped deletes are safe), and the six in-memory per-character maps. (The old
  /// stub dropped only five of the maps and never touched the DB row or avatar.)
  Future<void> _deleteMemberCleanup(String charId, String? avatarFilename) async {
    final groupId = _activeGroup?.id;
    await _db.deleteGroupMember(charId);
    if (groupId != null && avatarFilename != null) {
      try {
        final f = File(
          path.join(
            _storageService.groupsDir.path,
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
    // charId == the member's unique instance UUID, so these never touch another
    // character's rows.
    await _db.deleteObjectivesForCharacter(charId);
    await _db.deleteEmbeddingsForCharacter(charId);
    await _db.deleteDataBankEntriesForCharacter(charId);
    _groupRealism.remove(charId);
    _groupAuthorNotes.remove(charId);
    _groupAuthorNoteStrengths.remove(charId);
    _groupCharacterSystemPrompts.remove(charId);
    _groupCharacterRAGPriorities.remove(charId);
    _groupObjectives.remove(charId);
    // Growth rings — a hard-removed member leaves no growth residue behind
    // (mirrors the objectives/embeddings deletes above; charId is the unique
    // member instance id, so this never touches another character's rings).
    if (_currentSessionId != null) {
      await _growthStore.deleteAllFor(_currentSessionId!, charId);
      await _refreshGrowthCache();
    }
  }

  /// Automatically collapse a group that has dropped to a SINGLE member back
  /// into a 1:1 with that member's ORIGINAL library character (a one-character
  /// group is nonsense). Re-homes the CURRENT session in place (keeps all
  /// history), carries the survivor's realism back into the 1:1 scalar columns
  /// (the inverse of Phase 2's [_carryHostStateIntoForkedGroup]), then
  /// dissolves the now-empty group (member rows + private avatars + definition).
  ///
  /// If the survivor's origin can't be resolved (legacy/ambiguous — see
  /// [MemberOriginResolver]) it stays a one-member cast rather than guessing.
  /// Returns true if it collapsed.
  Future<bool> _collapseGroupToSolo(GroupChatRepository groupRepo) async {
    final group = _activeGroup;
    final sessionId = _currentSessionId;
    if (group == null || sessionId == null) return false;
    if (_groupCharacters.length != 1) return false;

    final sole = _groupCharacters.first;
    final soleId = _getCharacterIdFromCard(sole); // member instance id (mid)

    // Resolve the survivor back to its origin library character (Phase 1). The
    // origin link lives on the member ROW (memberState), not the loaded card.
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
      libraryCharacters:
          _characterRepository?.characters ?? const <CharacterCard>[],
    );
    if (origin == null || origin.dbId == null) {
      debugPrint('[Cast] collapse skipped: ${sole.name} origin unresolvable');
      _setGuestStatus(
        '⚠ Couldn’t match ${sole.name} back to a library character, so this '
        'stays a group. (Re-import or rename it to match the original.)',
        isError: true,
      );
      notifyListeners();
      return false;
    }

    // Safety: only auto-dissolve when THIS is the group's only session. Dissolving
    // (groupRepo.delete) hard-deletes every session of the group AND its messages,
    // so if the user started other conversations in this group, collapsing here
    // would destroy them. In that (rare) case stay a one-member cast instead.
    final groupSessions = await _db.getSessionsForGroup(group.id);
    if (groupSessions.length > 1) {
      debugPrint(
        '[Cast] collapse skipped: group "${group.name}" has '
        '${groupSessions.length} sessions — not auto-dissolving (would lose history)',
      );
      _setGuestStatus(
        '⚠ This group has other saved conversations, so it can’t auto-collapse '
        'to a 1:1. Delete the other group chats first.',
        isError: true,
      );
      notifyListeners();
      return false;
    }

    // 1) While still in group mode, capture the survivor's full state to carry
    //    back to the 1:1: the realism snapshot (gated on realism being on) PLUS
    //    the enable-flags, author note, and evolution (carried regardless of
    //    realism). originId = the id the collapsed 1:1 will key realism/memory by.
    final originId = _getCharacterIdFromCard(origin);
    final bool wasRealismOn = _realismEnabled;
    final bool wasNeedsOn = _needsSimEnabled;
    Map<String, dynamic>? snapshot;
    if (wasRealismOn) {
      _loadGroupRealismIntoScalars(soleId); // loads the survivor's per-char nsfw flag too
      snapshot = _captureRealismState();
    }
    // Read the survivor's per-char NSFW flag straight from the group store (the
    // per-speaker load only ran above when realism is on; reading the live nsfw
    // scalar otherwise could pick up a stale impersonated value).
    final bool soleNsfwEnabled =
        (_groupRealism[soleId]?['nsfwCooldownEnabled'] as bool?) ??
        _nsfwService.nsfwCooldownEnabled;
    final bool solePassageEnabled = _timeService.passageOfTimeEnabled;
    final bool soleChaosEnabled = _chaosModeService.chaosModeEnabled;
    final int soleChaosPressure = _chaosModeService.chaosPressure;
    final String soleAuthorNote = _groupAuthorNotes[soleId] ?? '';
    final int soleAuthorStrength = _groupAuthorNoteStrengths[soleId] ?? 4;
    // Any undistilled legacy evolved text (pre-rings growth) moves from the
    // group JSON maps to the 1:1 columns after re-home, so the distill
    // migration still finds it. Rings themselves re-key in place below.
    String soleLegacyPers = '';
    String soleLegacyScen = '';
    try {
      final sessRow = await _db.getSessionById(sessionId);
      if (sessRow != null) {
        soleLegacyPers =
            _tryParseJsonMap(sessRow.groupEvolvedPersonalities)[soleId] ?? '';
        soleLegacyScen =
            _tryParseJsonMap(sessRow.groupEvolvedScenarios)[soleId] ?? '';
      }
    } catch (_) {}

    // 2) Re-home the session to a 1:1 owned by the library character. Bump
    //    createdAt so setActiveCharacter's most-recent-session load lands on
    //    exactly this session; clear group_realism_state so the 1:1 load doesn't
    //    try to hydrate group state.
    final reHomed = await _db.patchSession(
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
      // Session row not found — abort BEFORE dissolving so we never delete the
      // group while its session is still group-homed (which would orphan it).
      debugPrint('[Cast] collapse aborted: re-home patchSession matched no row');
      notifyListeners();
      return false;
    }

    // 3) Dissolve the now-empty group: member rows + private avatars + the group
    //    definition. The re-homed session's groupId is null, so the repo's
    //    by-groupId session sweep cannot touch it (its history survives).
    await groupRepo.delete(group.id);

    // Carry the survivor's group-era objectives + semantic memory (RAG
    // embeddings) into the collapsed 1:1 by RE-KEYING them from the member
    // instance id (and the group RAG key 'group_<id>') to the origin library id,
    // so quests and conversation memory survive the collapse instead of being
    // deleted. (Data-bank rows are rarely used and not re-keyed.)
    try {
      await _db.reassignObjectives(soleId, originId, chatId: sessionId);
      await _db.reassignGrowthRings(soleId, originId, sessionId: sessionId);
      await _db.reassignEmbeddings(
        'group_${group.id}',
        originId,
        chatId: sessionId,
      );
      await _db.deleteDataBankEntriesForCharacter(soleId);
    } catch (e) {
      debugPrint('[Cast] state re-key (non-fatal): $e');
    }

    // 4) Re-enter as a 1:1 on the re-homed session (newest → loaded). Safety net:
    //    force the exact session if some other session of this character is newer.
    await setActiveCharacter(origin);
    if (_currentSessionId != sessionId) {
      await loadSession(sessionId);
    }

    // 5) Restore the carried state into the 1:1 (setActiveCharacter reset it; the
    //    re-homed session's stale columns are overwritten here with the
    //    survivor's state). Realism values are gated on realism being on; the
    //    enable-flags, author note and evolution carry regardless.
    if (wasRealismOn && snapshot != null) {
      _realismEnabled = true;
      _needsSimEnabled = wasNeedsOn;
      _relationshipService.restoreFromMessageState(snapshot);
      _moodDecayCounter =
          (snapshot['moodDecayCounter'] as int?) ?? _moodDecayCounter;
      _characterEmotion =
          (snapshot['characterEmotion'] as String?) ?? _characterEmotion;
      _emotionIntensity =
          (snapshot['emotionIntensity'] as String?) ?? _emotionIntensity;
      _nsfwService.restoreNsfwFromMessageState(snapshot);
      _timeService.restoreTimeFromRealismState(snapshot);
      if (wasNeedsOn) {
        final needs = snapshot['needs'];
        if (needs is Map && needs['vector'] is Map) {
          _needsSimulation.restoreFromSnapshot({
            'vector': Map<String, int>.from(needs['vector'] as Map),
          });
        } else {
          _needsSimulation.initializeFresh();
        }
      } else {
        _needsSimulation.clearVector();
      }
    }

    // Enable-flags + author note (persisted by _doSaveChat below) — carry
    // regardless of realism so the NSFW toggle, passage-of-time, chaos, and the
    // note are not reset to defaults on collapse.
    _nsfwService.setNsfwCooldownEnabled(soleNsfwEnabled);
    _timeService.setPassageOfTimeEnabled(solePassageEnabled);
    _chaosModeService.loadScalars(
      modeEnabled: soleChaosEnabled,
      pressure: soleChaosPressure,
    );
    _authorNote = soleAuthorNote;
    _authorNoteStrength = soleAuthorStrength;

    // Growth rings were re-keyed in place above (soleId → originId, same
    // session — rings are session-scoped, so the collapse costs nothing).
    // Move any undistilled legacy evolved text to the 1:1 columns.
    if (soleLegacyPers.isNotEmpty || soleLegacyScen.isNotEmpty) {
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(sessionId),
          evolvedPersonality: drift.Value(soleLegacyPers),
          evolvedScenario: drift.Value(soleLegacyScen),
          groupEvolvedPersonalities: const drift.Value('{}'),
          groupEvolvedScenarios: const drift.Value('{}'),
        ),
      );
    }
    await _refreshGrowthCache();
    await _saveChat();
    notifyListeners();
    debugPrint('[Cast] collapsed group "${group.name}" → 1:1 with ${origin.name}');
    return true;
  }

  /// Carry the host's full captured 1:1 [state] (taken before the fork switched
  /// into group mode) onto the host member, making 1:1->group lossless. The
  /// realism snapshot is applied only when realism was on at fork time; the
  /// enable-flags (NSFW/passage-of-time/chaos), the per-character author note,
  /// character evolution (into the group_evolved_* columns), and a COPY of the
  /// host's objectives all carry REGARDLESS of realism. No-op when the host
  /// member can't be resolved (so a mis-keyed carry can't corrupt state).
  /// [originalCharId] / [hostSessionId] are the host's 1:1 keys (evolution +
  /// objectives source).
  Future<void> _carryHostStateIntoForkedGroup(
    String hostName,
    String originalCharId,
    String? hostSessionId,
    Map<String, dynamic> state,
  ) async {
    if (_activeGroup == null) return;
    CharacterCard? hostMember;
    for (final c in _groupCharacters) {
      if (c.name == hostName) {
        hostMember = c;
        break;
      }
    }
    if (hostMember == null) return; // host member not found — don't mis-key
    final hostId = _getCharacterIdFromCard(hostMember);
    final realismOn = state['realismOn'] as bool? ?? false;
    final needsEnabled = state['needsSimEnabled'] as bool? ?? false;
    _needsSimEnabled = needsEnabled;

    // Realism VALUES (gated on realism being on at fork time): relationship +
    // emotion + nsfw + time via the regenerate restore path, then the canonical
    // _groupRealism write for the host member.
    if (realismOn) {
      _realismEnabled = true;
      _relationshipService.restoreFromMessageState(state);
      _moodDecayCounter =
          (state['moodDecayCounter'] as int?) ?? _moodDecayCounter;
      _characterEmotion =
          (state['characterEmotion'] as String?) ?? _characterEmotion;
      _emotionIntensity =
          (state['emotionIntensity'] as String?) ?? _emotionIntensity;
      _nsfwService.restoreNsfwFromMessageState(state);
      _timeService.restoreTimeFromRealismState(state);
      if (needsEnabled) {
        final needs = state['needs'];
        if (needs is Map && needs['vector'] is Map) {
          _needsSimulation.restoreFromSnapshot({
            'vector': Map<String, int>.from(needs['vector'] as Map),
          });
        } else {
          _needsSimulation.initializeFresh();
        }
      } else {
        _needsSimulation.clearVector();
      }
      _saveScalarsIntoGroupRealism(hostId);
    }

    // Enable-flags (independent of realism; persist via _doSaveChat columns in
    // both modes) + author note + evolution + objectives carry REGARDLESS.
    _nsfwService.setNsfwCooldownEnabled(
      state['nsfwCooldownEnabled'] as bool? ?? false,
    );
    _timeService.setPassageOfTimeEnabled(
      state['passageOfTimeEnabled'] as bool? ?? true,
    );
    _chaosModeService.loadScalars(
      modeEnabled: state['chaosModeEnabled'] as bool? ?? false,
      pressure: state['chaosPressure'] as int? ?? 0,
    );

    // Author note -> the host member's per-character group note (serialized into
    // group_realism_state by _saveChat).
    final note = state['authorNote'] as String? ?? '';
    if (note.isNotEmpty) {
      _groupAuthorNotes[hostId] = note;
      _groupAuthorNoteStrengths[hostId] =
          state['authorNoteStrength'] as int? ?? 4;
    }

    // COPY the host's 1:1 objectives + RAG memory + growth onto the new group
    // so nothing is lost on conversion (COPY, not move — the original 1:1
    // stays the revert snapshot; collapse re-keys these in place instead).
    if (hostSessionId != null && _currentSessionId != null) {
      // Growth rings + any undistilled legacy evolved text -> the host MEMBER
      // instance id in the new group session (the legacy blob lands in the
      // group_evolved_* maps so the distill migration still finds it there).
      await _growthStore.carryOwnerGrowth(
        fromSessionId: hostSessionId,
        fromCharId: originalCharId,
        toSessionId: _currentSessionId!,
        toCharId: hostId,
        fromIsGroup: false,
        toIsGroup: true,
      );
      await _refreshGrowthCache();
      // Objectives -> the host MEMBER instance id + new group session.
      final origObjs = await _db.getObjectivesForCharacter(
        originalCharId,
        chatId: hostSessionId,
      );
      for (final o in origObjs) {
        await _db.insertObjective(
          ObjectivesCompanion.insert(
            id: const Uuid().v4(),
            characterId: hostId,
            objective: o.objective,
            chatId: drift.Value(_currentSessionId),
            tasks: drift.Value(o.tasks),
            active: drift.Value(o.active),
            isPrimary: drift.Value(o.isPrimary),
            checkFrequency: drift.Value(o.checkFrequency),
            injectionDepth: drift.Value(o.injectionDepth),
          ),
        );
      }
      // RAG memory -> the GROUP's shared pool (keyed 'group_<id>' via
      // _getCharacterId, not per-member) so the cast can recall pre-conversion
      // events that scrolled out of context.
      try {
        await _db.copyEmbeddingsForSession(
          originalCharId,
          hostSessionId,
          toCharacterId: _getCharacterId(),
          toSessionId: _currentSessionId!,
        );
      } catch (e) {
        debugPrint('[Cast] host RAG carry-on-fork (non-fatal): $e');
      }
    }

    await _saveChat();
    notifyListeners();
  }
}
