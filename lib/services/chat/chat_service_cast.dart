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
    if (_activeGroup == null || _isTurnBusy) return false;
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
    await _saveChat();
    notifyListeners();
    return true;
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
      await _refreshGrowthCache();
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
