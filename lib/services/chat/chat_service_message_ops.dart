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

/// Message-list mutation: swipe, continue, session reload/clear/delete,
/// [deleteMessage], generation cancel, [cancelRealismEval]. Timeline
/// invalidation lives in chat_service_timeline.dart.
extension ChatServiceMessageOps on ChatService {
  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(int messageIndex, int direction) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;

    final newIndex = msg.swipeIndex + direction;

    // Swiping left
    if (direction < 0) {
      if (newIndex >= 0) {
        await _commitSwipeIndex(messageIndex, newIndex);
      }
      return;
    }

    // Swiping right
    if (newIndex < msg.swipes.length) {
      await _commitSwipeIndex(messageIndex, newIndex);
    } else if (messageIndex == _messages.length - 1) {
      // Past last swipe on last message — regenerate (aborts settling evals)
      await regenerateLastMessage();
    }
  }

  /// Apply an already-stored swipe index. Guest replies never rewind
  /// Realism/Needs; only the tip of the chat restores that snapshot
  /// (re-reading an old variant is navigation, not time travel).
  Future<void> _commitSwipeIndex(int messageIndex, int newIndex) async {
    final msg = _messages[messageIndex];
    if (newIndex == msg.swipeIndex) return;
    if (newIndex < 0 || newIndex >= msg.swipes.length) return;

    final isGuestMsg = _isGuestAuthoredMessage(msg);
    final isTip =
        !isGuestMsg &&
        _messages.skip(messageIndex + 1).every(_isGuestAuthoredMessage);

    msg.swipeIndex = newIndex;
    if (isTip) _syncRealismStateForSwipe(msg);
    // Pockets follow the selected variant too — this swipe's own
    // post-turn record, or the shared pre-turn base when this variant's
    // pass changed nothing (hostile review 2026-08-11).
    if (isTip) _restorePocketsFromStamp(msg, after: true);
    // Timeline integrity follows the same tip-only rule pockets/realism
    // already use. A TIP swipe is a suffix rewrite: Journal/Growth/RAG
    // citing this position and later describe events that no longer
    // happened, then this variant's item cards are re-sown. A buried
    // swipe is navigation — later memories stay on screen AND in the
    // diary; only this variant's item cards are re-sown.
    if (isTip) {
      _invalidateJournalFrom(
        persistMessagePosition(
          base: _history.basePosition,
          index: messageIndex,
        ),
        thenReplantPlanted: msg,
      );
    } else {
      unawaited(_replantItemCards(msg, key: 'item_cards_planted'));
    }
    await _saveChat();
    notifyListeners();
  }

  void _syncRealismStateForSwipe(ChatMessage msg) {
    if (!_realismEnabled) return;

    // Natively restore the frozen runtime variables for the selected alternate
    // timeline — in groups, into the swiped speaker's own _groupRealism entry.
    _restoreRealismStateForSpeaker(msg);
  }

  /// Abort in-flight post-gen evals so a mutation (regen/continue) can
  /// start. Streaming (`_isGenerating`) and import still refuse — those
  /// are not "I already have the reply and I don't want it scored."
  Future<bool> _yieldSettlingTurn() async {
    if (_isGenerating || _isImporting) return false;
    if (!_isPostGenerating) return true;
    _postGenAbortRequested = true;
    _isCancellingRealismEval = true;
    _realismEvalCancelled = true;
    try {
      (testLlmServiceOverride ?? _llmProvider?.activeService)
          ?.abortGeneration();
    } catch (_) {}
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_isPostGenerating && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    // Do not clear abort flags here. If we timed out, post-gen is still
    // running and must keep skipping applies. The finishing generate
    // finally clears the flags when settling actually drops.
    return !_isPostGenerating;
  }

  Future<void> continueGeneration() async {
    if (_messages.isEmpty || _sceneGuest.busy) return;
    // Continue KEEPS the reply. Aborting its scoring would leave the first
    // half unbookkept and only score the new fragment. Wait like Send.
    if (_isGenerating || _isImporting) return;
    if (_isPostGenerating) await _waitForTurnToSettle();

    // Only continue if the last message is from a bot (non-user, non-system).
    // Narration banners (dreams, Chance Time) are excluded: continue_ streams
    // straight into _messages.last, which would append a chat reply to the
    // banner (the dream-corruption class, 2026-07-28).
    if (!_messages.last.isUser &&
        _messages.last.sender != 'System' &&
        _messages.last.activeMetadata?['is_dream'] != true &&
        _messages.last.activeMetadata?['is_chance_time_narration'] != true) {
      await _generateResponse(GenerationMode.continue_);
    }
  }

  /// Reload the current session from the database without clearing messages first.
  /// Used after cloud sync or DB migration updates the database — preserves the
  /// user's active chat instead of wiping it.
  Future<void> reloadCurrentSession() async {
    if (_currentSessionId == null) return;
    debugPrint(
      '[ChatService] 🔄 reloadCurrentSession: reloading session $_currentSessionId '
      '(currently ${_messages.length} messages in memory)',
    );
    await loadSession(_currentSessionId!);
  }

  void clearChat() async {
    debugPrint(
      '[ChatService] 🟡 clearChat: clearing ${_messages.length} messages',
    );
    _messages.clear();
    await _saveChat();
    notifyListeners();
  }

  /// Delete a specific chat session and its messages.
  /// If it's the current session, switches to the most recent remaining one.
  ///
  /// [startReplacement] is the in-chat folder behaviour (default): when the
  /// deleted id is the open session and nothing remains, [startNewChat] so
  /// the user is not left staring at a missing chat. Home / the web library
  /// pass false so emptying a card's history does not spawn a replacement.
  Future<void> deleteSession(
    String sessionId, {
    bool startReplacement = true,
  }) async {
    await _db.deleteMessagesForSession(sessionId);
    await _db.deleteSessionById(sessionId);

    // If we deleted the current session, switch to another
    if (sessionId == _currentSessionId) {
      final remaining = await getSessions();
      if (remaining.isNotEmpty) {
        if (startReplacement) {
          await loadSession(remaining.first['id']);
        } else {
          _messages.clear();
          _currentSessionId = null;
        }
      } else {
        // No sessions left — start fresh only when the open chat asked.
        debugPrint(
          '[ChatService] 🟡 deleteSession: no sessions left, clearing messages',
        );
        _messages.clear();
        _currentSessionId = null;
        if (startReplacement) {
          await startNewChat();
        }
      }
    }
    notifyListeners();
  }

  void deleteMessage(int index) async {
    // No deletes while a generation is live: removing entries shifts every
    // position the active turn still relies on (chip attach, lorebook scan,
    // journal invalidation) — and made a dream banner the last message,
    // where the aborted turn's writes landed (2026-07-28). Stop first.
    if (_isTurnBusy) return;
    if (index < 0 || index >= _messages.length) return;
    final dbPos = persistMessagePosition(
      base: _history.basePosition,
      index: index,
    );
    final wasTail = index == _messages.length - 1;
    // Middle-of-history delete needs the full prefix so replaceAll
    // cannot drop the 11k rows we have not loaded yet.
    if (!wasTail && _history.hasMore) {
      await _awaitHistoryHydrated();
      index = dbPos;
      if (index < 0 || index >= _messages.length) return;
    }
    if (index >= 0 && index < _messages.length) {
      final deleted = _messages[index];

      // Pockets stamp restore runs AFTER realism time-travel below (not
      // here). realism_state.pockets was historically pre-gen and, even
      // when restamped post-gen, restoring the NEW last message must not
      // clobber the deleted turn's pre-ops rewind for the deleted speaker
      // (and any hand-off recipients). Stamp wins last on tail deletes.

      // Needs are refunded by ARITHMETIC (subtract this message's own chips),
      // not by the realism time-travel below — that only ever rewinds the
      // tail, so deleting anything older left its needs cost applied forever.
      // Capture the deleted speaker's needs BEFORE the restore runs; the
      // refund is settled from this baseline afterwards.
      final deletedSpeaker = (!deleted.isUser && deleted.sender != 'System')
          ? _resolveGroupSpeakerForMessage(deleted)
          : null;
      final String? deletedSid =
          (_activeGroup != null && deletedSpeaker != null)
          ? _getCharacterIdFromCard(deletedSpeaker)
          : null;
      // In a group, refund ONLY when the speaker resolved unambiguously —
      // falling back to the live scalars there would credit whichever member
      // happens to be loaded, i.e. refund the wrong character. An empty
      // baseline makes the revert a no-op.
      final Map<String, int> needsBeforeDelete =
          (!_needsSimEnabled || (_activeGroup != null && deletedSid == null))
          ? const <String, int>{}
          : (deletedSid != null
                ? Map<String, int>.from(_getGroupNeeds(deletedSid))
                : Map<String, int>.from(_needsSimulation.vector));

      _messages.removeAt(index);

      // Persist index, not the on-screen 0..23 of a tail window.
      _invalidateJournalFrom(dbPos);

      // Time-travel rollback for realism when deleting a character message.
      // Restore from the new last message if it has a snapshot, regardless
      // of whether this was the last message. This ensures needs state
      // (and all realism fields) reset to their previous saved values — in
      // groups, inside the NEW LAST speaker's own _groupRealism entry.
      if (_messages.isNotEmpty) {
        final newLast = _messages.last;
        _restoreRealismStateForSpeaker(newLast);
      }

      // Group: also roll back the DELETED speaker's OWN _groupRealism entry to
      // their previous stamped turn — otherwise that member's bond/trust/needs
      // deltas from the removed message stand forever (the state machine only
      // rewinds whoever is now last). Guards:
      //   • the deleted message must itself carry a realism_state — otherwise
      //     it applied no deltas and rewinding would INVENT older history;
      //   • the sender name must be unambiguous in the roster — restore resolves
      //     by name (_restoreRealismStateForSpeaker), so with two same-named
      //     members it could rewind the wrong one; skip that rare case rather
      //     than corrupt state;
      //   • skip when the deleted speaker is already the new-last (handled
      //     above) or has no earlier stamped turn.
      if (_activeGroup != null &&
          !deleted.isUser &&
          deleted.sender != 'System' &&
          deleted.activeMetadata?['realism_state'] is Map &&
          deletedSid != null &&
          (_messages.isEmpty ||
              _resolveGroupSpeakerForMessage(_messages.last) !=
                  deletedSpeaker)) {
        for (int i = _messages.length - 1; i >= 0; i--) {
          final m = _messages[i];
          final speaker = _resolveGroupSpeakerForMessage(m);
          if (speaker != null &&
              _getCharacterIdFromCard(speaker) == deletedSid &&
              m.activeMetadata?['realism_state'] is Map) {
            _restoreRealismStateForSpeaker(m);
            break;
          }
        }
      }

      // Settle needs LAST so it wins over whatever the snapshot restores did
      // to the vector (see _revertNeedsForDeletedMessage).
      _revertNeedsForDeletedMessage(
        deleted,
        needsBeforeDelete,
        groupSid: deletedSid,
      );

      if (!deleted.isUser && deleted.sender != 'System') {
        _rewindPocketsForDeletedMessage(deleted, wasTail: wasTail);
        if (wasTail) {
          final before =
              deleted.activeMetadata?['story_clock_before'] as String?;
          if (_clockRunning && StoryClock.parse(before) != null) {
            _timeService.restoreTimeFromRealismState({'storyClock': before});
          }
        }
      }

      if (wasTail && _history.hasMore) {
        await _saveChat(replaceAll: false);
        final sid = _currentSessionId;
        if (sid != null) {
          await _db.deleteMessagesAtPosition(sid, dbPos);
        }
      } else {
        await _saveChat(replaceAll: true);
      }
      notifyListeners();
    }
  }

  void stopGeneration() {
    if (_isGenerating) {
      _cancelRequested = true;
      // Abort the in-flight HTTP request so we don't have to wait for the next token
      (testLlmServiceOverride ?? _llmProvider?.activeService)
          ?.abortGeneration();
    }
  }

  /// Cancel any in-flight generation and wait for it to fully stop.
  Future<void> _cancelAndWaitForGeneration() async {
    if (!_isGenerating) return;
    _cancelRequested = true;
    // Spin until _generateResponse finishes its cleanup
    while (_isGenerating) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void _rewindPocketsForDeletedMessage(
    ChatMessage deleted, {
    required bool wasTail,
  }) {
    if (wasTail) {
      _restorePocketsFromStamp(deleted, after: false);
      return;
    }
    unawaited(_replantItemCards(deleted, key: 'item_cards_retired'));
    if (!_storageService.realismSettings.pocketsEnabled) return;
    final before = deleted.metadata?['pockets_before'];
    if (before is! Map) return;
    final speakerId = before['char'];
    if (speakerId is! String || speakerId.isEmpty) return;
    final othersBefore = <String, Pockets>{};
    final rawOthers = before['others'];
    if (rawOthers is List) {
      for (final o in rawOthers) {
        if (o is Map && o['char'] is String) {
          othersBefore[o['char'] as String] = Pockets.fromJson(o['record']);
        }
      }
    }
    final othersAfter = <String, Pockets>{};
    final rawAfter = deleted.activeMetadata?['pockets_after_others'];
    if (rawAfter is List) {
      for (final o in rawAfter) {
        if (o is Map && o['char'] is String) {
          othersAfter[o['char'] as String] = Pockets.fromJson(o['record']);
        }
      }
    }
    final ids = <String>{
      speakerId,
      ...othersBefore.keys,
      ...othersAfter.keys,
      if (_activeGroup != null)
        for (final c in _groupCharacters) _getCharacterIdFromCard(c),
      if (_activeGroup == null && _activeCharacter != null)
        _getCharacterIdFromCard(_activeCharacter!),
    };
    final live = <String, Pockets>{
      for (final id in ids)
        if (id.isNotEmpty) id: (pocketsFor(id) ?? Pockets()).copy(),
    };
    invertDeletedPocketTurn(
      speakerId: speakerId,
      speakerBefore: Pockets.fromJson(before['record']),
      speakerAfter: pocketsStamp(deleted.activeMetadata?['pockets_after']),
      othersBefore: othersBefore,
      othersAfter: othersAfter,
      live: live,
    );
    for (final e in live.entries) {
      setPocketsFor(e.key, e.value);
    }
  }

  /// Cancel an in-progress Realism evaluation stream (if any).
  ///
  /// Behavior:
  /// - If there is no active realism evaluation and no post-greeting processing,
  ///   this is a no-op.
  /// - Mark cancelling flag, attempt to abort the underlying generation, then
  ///   reset all related UI/state and emit a final notification.
  /// - Do not restart any ongoing flow automatically after cancellation.
  Future<void> cancelRealismEval() async {
    // No-op if there is nothing to cancel
    if (!_isEvaluatingRealism && !_isProcessingGreeting) {
      debugPrint('[Realism] Cancel request ignored — no active realism eval.');
      return;
    }

    _isCancellingRealismEval = true;
    // Signal to any ongoing realism evaluation that a cancel has been requested.
    _realismEvalCancelled = true;
    notifyListeners();

    // Transient banner only — NEVER a chat message. The old code appended an
    // "evaluation interrupted" line attributed to the character, which then
    // permanently rode chat history, prompts, RAG, and journal windows.
    _setGuestStatus(
      'Realism evaluation cancelled — no reply was generated. '
      'Regenerate (or send again) to retry.',
    );

    final llmService =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;
    debugPrint('[Realism] Realism eval cancel requested');
    try {
      llmService.abortGeneration();
      debugPrint('[Realism] abortGeneration invoked');
    } catch (e) {
      // Ensure we always proceed to reset state even if abortion fails unexpectedly
      debugPrint('[Realism cancel] Unexpected error during abort: $e');
    } finally {
      // Reset all realism-related state
      _realismEvalStreamText = '';
      _pendingRealismMetadata = null;
      _isEvaluatingRealism = false;
      _isProcessingGreeting = false;
      _isCancellingRealismEval = false;
      // NOTE: Do NOT reset _realismEvalCancelled here. It must remain true so that
      // sendMessage() can detect the cancellation and return early. The flag is only
      // reset in sendMessage() after the cancellation is properly handled.
      notifyListeners();
    }
  }
}
