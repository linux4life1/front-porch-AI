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

/// Why [ChatServiceCast.canRemoveCastMember] refused a member's exit.
const kDirectorCastFloorNote =
    'While you direct, the scene keeps at least two characters. Step back '
    'in with /director off first.';

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
  ///   3. The destructive removal is deferred to [_commitPendingMemberExit],
  ///      which fires from `sendMessage` the moment the user continues — so
  ///      [undoLastExit] in the meantime restores them exactly. An exit that
  ///      leaves one character commits at once instead: the group turns back
  ///      into a 1:1 there and then, with no UNDO, rather than sitting as a
  ///      one-member group under the old group header until the next send.
  /// Unlike a Lite guest (never deleted, so undo is trivial), a full member is a
  /// real row; deferring the delete is what makes the undo lossless. Returns true
  /// once the goodbye is staged and the exit is pending.
  Future<bool> exitGroupMember(
    CharacterCard member,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _isTurnBusy) return false;
    // Finalize any prior pending exit before starting a new one — the UNDO only
    // ever applies to the most recent `/exit`, so a second exit commits the
    // first. That commit may have collapsed the group or removed this member, so
    // re-check before proceeding (a no-op in the normal single-exit case).
    await _commitPendingMemberExit();
    if (_activeGroup == null) return false;
    if (!canRemoveCastMember) {
      _setGuestStatus(kDirectorCastFloorNote, isError: true);
      return false;
    }
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
    final before = _messages.length;
    try {
      await _generateResponse(GenerationMode.normal);
    } catch (e) {
      debugPrint('[Cast] exit narration for ${member.name} failed: $e');
      _entranceDirective = null; // don't leak into a later turn
    }
    await _dropSilentStagedTurn(before);
    // 2. Soft-remove from the live roster only — nothing on disk is touched, so
    //    the removal stays fully reversible until the user continues.
    final memberId = _getCharacterIdFromCard(member);
    final remaining = _groupCharacters
        .where((c) => _getCharacterIdFromCard(c) != memberId)
        .toList();
    if (remaining.length < 2) {
      _clearExitUndo();
      await _waitForTurnToSettle();
      if (await removeCharacterFromGroup(member, groupRepo)) return true;
      // Still busy: the next send commits it, as for any exit.
    }
    _groupManager?.refreshCharacters(remaining);
    _sceneGuest.pendingMemberExit = member;
    // 3. Arm the UNDO snackbar; the just-generated goodbye turn is what undo
    //    deletes (its realism rollback included). Mirrors armSceneGuestExitUndo
    //    but without the lite `_sceneGuest.exitUndoGuest` marker so undoLastExit takes the
    //    group branch.
    _sceneGuest.exitUndoMessage =
        (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.sender != 'System')
        ? _messages.last
        : null;
    _sceneGuest.exitUndoOfferName = member.name;
    _sceneGuest.exitUndoUserStep = false; // UNDO now means this exit
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// Whether a member may leave now. While the user directs, the scene keeps
  /// two characters: one left would turn the group back into a 1:1 and end
  /// Director Mode under the next note.
  bool get canRemoveCastMember =>
      _groupCharacters.length > (_directing ? 2 : 1);

  /// `/director`: {{user}} steps out of a group scene to direct it, with the
  /// same narrated departure and UNDO as a full member's `/exit`. The next
  /// character reacts to them leaving, then Director Mode comes on. The
  /// goodbye turn scores nothing (skipSpeakerEval): nobody said anything
  /// new to anyone, and the judges already scored the last real line.
  Future<bool> stepUserOffStage() async {
    if (_activeGroup == null || _observerMode || _isTurnBusy) return false;
    // An open member-exit undo window closes here, as a send would close it.
    await _commitPendingMemberExit();
    _clearExitUndo();
    if (_activeGroup == null) return false;
    final name = _userPersonaService.persona.name;
    final before = _messages.length;
    _entranceDirective = userStepsOutDirective(name);
    try {
      await _generateResponse(GenerationMode.normal, skipSpeakerEval: true);
    } catch (e) {
      debugPrint('[Director] step-out narration failed: $e');
      _entranceDirective = null; // don't leak into a later turn
    }
    await _dropSilentStagedTurn(before);
    _observerMode = true;
    final last = _messages.lastOrNull;
    _sceneGuest.exitUndoUserStep = true;
    _sceneGuest.exitUndoMessage =
        (_messages.length > before &&
            last != null &&
            !last.isUser &&
            last.sender != 'System')
        ? last
        : null;
    _sceneGuest.exitUndoOfferName = name;
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// `/director off`: {{user}} walks back in. Director Mode goes off first,
  /// so the next character sees the user present and greets them. Like the
  /// goodbye, the greeting turn scores nothing — the last user-side line is
  /// a director's note, which is not something the user said.
  Future<bool> stepUserOnStage() async {
    if (!_directing || _isTurnBusy) return false;
    _clearExitUndo();
    _observerMode = false;
    _entranceDirective = userReturnsDirective(_userPersonaService.persona.name);
    final before = _messages.length;
    try {
      await _generateResponse(GenerationMode.normal, skipSpeakerEval: true);
    } catch (e) {
      debugPrint('[Director] step-in narration failed: $e');
      _entranceDirective = null;
    }
    await _dropSilentStagedTurn(before);
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// Undo for `/director`: delete the goodbye turn (rewinding what it
  /// applied) and put {{user}} back on stage. False when the open undo is
  /// someone else's exit.
  Future<bool> _undoUserStepOut() async {
    if (!_sceneGuest.exitUndoUserStep) return false;
    final goodbye = _sceneGuest.exitUndoMessage;
    _clearExitUndo();
    if (goodbye != null) {
      final idx = _messages.indexOf(goodbye);
      if (idx >= 0) deleteMessage(idx); // removes + reverts realism + saves
    }
    _observerMode = false;
    await _saveChat();
    _setGuestStatus('You are back in the scene.');
    notifyListeners();
    return true;
  }

  /// The director's pinned scene goal, or empty.
  String get directorGoal => _directorScene.goal;

  /// The director's private whispers, by member id.
  Map<String, String> get directorWhispers => _directorScene.whispers;

  /// The whispers for members still in the scene, in cast order.
  List<({String id, String name, String text})> get directorWhisperRows => [
    for (final c in _groupCharacters)
      if (_directorScene.whispers[_getCharacterIdFromCard(c)] case final w?)
        (id: _getCharacterIdFromCard(c), name: c.name, text: w),
  ];

  /// Pins [text] as the scene goal; empty clears it. Saved per chat.
  Future<void> setDirectorGoal(String text) async {
    if (_activeGroup == null) return;
    _directorScene.setGoal(text);
    await _saveChat();
    notifyListeners();
  }

  /// Sets the private whisper for the member with [memberId]; empty clears it.
  Future<void> setDirectorWhisper(String memberId, String text) async {
    if (_activeGroup == null) return;
    final known = _groupCharacters.any(
      (c) => _getCharacterIdFromCard(c) == memberId,
    );
    // A stale id can only be cleared; it never gains a whisper.
    if (!known && text.trim().isNotEmpty) return;
    _directorScene.setWhisper(memberId, text);
    await _saveChat();
    notifyListeners();
  }

  /// The narrator is writing a beat (a turn in all but name).
  bool get isNarrating => _narrating;

  /// `/narrate`: one narrator beat lands as a scene card, then the next
  /// character reacts to it as they would to a note. False when a turn is
  /// already running, or the user isn't directing. The narrator's call counts
  /// as a running turn ([_isTurnBusy]), so a note, a cue, an auto-chat tick or
  /// a chat switch waits for it; a beat that returns to another chat is
  /// dropped.
  Future<bool> narrateScene(String hint) async {
    if (!_directing || _isTurnBusy) return false;
    final token = _currentSessionId;
    // The beat closes the undo window the way a note does.
    await _commitPendingMemberExit();
    _clearExitUndo();
    if (_sceneChanged(token) || !_directing || _isTurnBusy) return false;
    _narrating = true;
    var landed = false;
    try {
      _setGuestStatus('The narrator sets the scene…', sticky: true);
      final recent = _messages.length > kNarrationHistoryLines
          ? _messages.sublist(_messages.length - kNarrationHistoryLines)
          : _messages;
      final raw = await _llmEvalEngine.fireLLMEval(
        narrationPrompt(
          recentLines: [
            for (final m in recent)
              if (!m.isStatusBanner && m.sender != 'System')
                m.toPromptHistoryLine(),
          ],
          castNames: [for (final c in _groupCharacters) c.name],
          hint: hint,
        ),
        label: 'narration',
      );
      if (_sceneChanged(token)) {
        _setGuestStatus(null);
        return true;
      }
      final beat = raw == null
          ? ''
          : cleanNarration(_llmEvalEngine.stripThinkBlocks(raw));
      if (beat.isEmpty || !_directing) {
        _setGuestStatus(
          '⚠ The narrator had nothing to add. Try again.',
          isError: true,
        );
        return true;
      }
      _setGuestStatus(null);
      _messages.add(narrationMessage(beat));
      await _saveChat();
      landed = true;
    } catch (e) {
      debugPrint('[Director] narration failed: $e');
      _setGuestStatus('⚠ The narrator could not set the scene.', isError: true);
      return true;
    } finally {
      _narrating = false;
      notifyListeners();
    }
    // No await since the flag dropped: the reply raises _isGenerating first.
    if (landed && !_sceneChanged(token)) {
      await _generateResponse(GenerationMode.normal);
    }
    return true;
  }

  /// A goodbye or greeting that was stopped before it said a word (or only
  /// thought) is not a turn: it goes, rather than staying as an empty
  /// "only thoughts" bubble. [before] is the transcript length before it.
  Future<void> _dropSilentStagedTurn(int before) async {
    final last = _messages.lastOrNull;
    if (_messages.length <= before || last == null || last.isUser) return;
    if (last.displayText.trim().isNotEmpty) return;
    await _waitForTurnToSettle();
    final idx = _messages.indexOf(last);
    if (idx >= 0) deleteMessage(idx); // removes + reverts realism + saves
  }

  /// Commit a deferred full-member `/exit`: run the real removal (and any
  /// collapse to a 1:1) now that the undo window has closed. No-op when nothing
  /// is pending. The goodbye turn was already narrated at exit time, so this only
  /// does the destructive half via the shared removal path.
  Future<void> _commitPendingMemberExit() async {
    final member = _sceneGuest.pendingMemberExit;
    _sceneGuest.pendingMemberExit = null;
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
  Future<void> _deleteMemberCleanup(
    String charId,
    String? avatarFilename,
  ) async {
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
      // Same reasoning for the diary: the removed member's journal cards are
      // keyed by this instance id, so nothing would ever read them again.
      await _moveJournalCards(_currentSessionId!, charId, null);
      await _growthDesk.refreshCache();
    }
  }

  // Collapse to 1:1 and the inverse 1:1→group carry live in
  // chat_service_cast_shrink.dart (same library).

  /// Move one owner's journal cards inside a chat: re-key them to [toCharacterId]
  /// (cast collapse — the diary follows its owner), or DELETE them when that is
  /// null (hard member removal — mirrors the growth-ring/objective deletes, so a
  /// removed member leaves no unreadable rows behind). Row-by-row on purpose:
  /// a per-owner diary is capped at a few dozen cards, and this keeps the
  /// re-key on the existing public store/db surface.
  Future<void> _moveJournalCards(
    String sessionId,
    String fromCharacterId,
    String? toCharacterId,
  ) async {
    final cards = await _journalStore.cardsFor(sessionId, fromCharacterId);
    for (final card in cards) {
      if (toCharacterId == null) {
        await _db.deleteJournalCard(card.id);
      } else {
        await _db.updateJournalCard(
          card.id,
          JournalMemoriesCompanion(
            characterId: drift.Value(toCharacterId),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );
      }
    }
  }
}
