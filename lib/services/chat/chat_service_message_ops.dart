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

/// Message-list mutation operations: swipe navigation, continue, session
/// reload/clear/delete, [deleteMessage] (the needs-refund + group
/// deleted-speaker rewind parity block), generation cancellation, Journal
/// timeline invalidation, and [cancelRealismEval]. Extracted verbatim from
/// `chat_service.dart` — zero behaviour change; `deleteMessage` in
/// particular moves whole, exactly as it was, because the needs-refund
/// arithmetic and the group rewind ordering are pinned by
/// `delete_message_needs_rollback_test.dart`.
extension ChatServiceMessageOps on ChatService {
  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(int messageIndex, int direction) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;

    final newIndex = msg.swipeIndex + direction;

    // Guest-message swipes carry no Realism/Needs, so navigating between them
    // must never touch the active character's state (parity) — true even for a
    // guest who has since left the scene, hence the authoritative check.
    final isGuestMsg = _isGuestAuthoredMessage(msg);

    // …and the state rewind belongs to the TIP of the chat only. Re-reading an
    // OLD variant is navigation, not time travel: restoring that message's
    // snapshot rewound bond/trust/emotion/arousal/needs/story clock/pockets to
    // that turn while every later message stayed, and the `_saveChat()` below
    // wrote the rewind onto the session row permanently. Same rule the delete
    // door states out loud ("restore from the NEW LAST message"). Guest
    // replies are transparent here — they stamp no Realism/Needs — so a host
    // buried only under guest chime-ins is still the tip, matching
    // regenerableHostBelowGuestsIndex.
    final isTip =
        !isGuestMsg &&
        _messages.skip(messageIndex + 1).every(_isGuestAuthoredMessage);

    // Swiping left
    if (direction < 0) {
      if (newIndex >= 0) {
        msg.swipeIndex = newIndex;
        if (isTip) _syncRealismStateForSwipe(msg);
        // Pockets follow the selected variant too — this swipe's own
        // post-turn record, or the shared pre-turn base when this variant's
        // pass changed nothing (hostile review 2026-08-11).
        if (isTip) _restorePocketsFromStamp(msg, after: true);
        // Timeline integrity: the active variant at this position changed —
        // cards journaled from the other swipe are now phantom.
        _invalidateJournalFrom(messageIndex);
        await _saveChat();
        notifyListeners();
      }
      return;
    }

    // Swiping right
    if (newIndex < msg.swipes.length) {
      // Navigate to existing swipe
      msg.swipeIndex = newIndex;
      if (isTip) _syncRealismStateForSwipe(msg);
      // Same pockets rewind as the left branch.
      if (isTip) _restorePocketsFromStamp(msg, after: true);
      // Timeline integrity — same as the left-swipe branch above.
      _invalidateJournalFrom(messageIndex);
      await _saveChat();
      notifyListeners();
    } else if (messageIndex == _messages.length - 1 && !_isTurnBusy) {
      // Past last swipe on last message — regenerate
      await regenerateLastMessage();
    }
  }

  void _syncRealismStateForSwipe(ChatMessage msg) {
    if (!_realismEnabled) return;

    // Natively restore the frozen runtime variables for the selected alternate
    // timeline — in groups, into the swiped speaker's own _groupRealism entry.
    _restoreRealismStateForSpeaker(msg);
  }

  Future<void> continueGeneration() async {
    if (_messages.isEmpty || _isTurnBusy || _sceneGuest.busy) return;

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

      // Timeline integrity: the delete rewrites history from [index] on
      // (later positions shift down), so cards citing that region and the
      // pass cursor both roll back — replaces the old cursor-decrement drift
      // fix, which kept phantom cards alive (smoke-test bug 2026-07-21).
      // (Growth uses a DB-backed per-session cursor; it re-reads its stored
      // index on the next pass.)
      _invalidateJournalFrom(index);

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

      // Pockets AFTER realism: the stamp is the truth for the discarded
      // turn (speaker + any transfer recipients). Runs only on tail
      // character deletes — same contract as before.
      if (wasTail && !deleted.isUser && deleted.sender != 'System') {
        _restorePocketsFromStamp(deleted, after: false);
        // Clock: previous bot may be a Scene Guest with no realism_state,
        // so the snapshot restore above is a no-op. This turn's own
        // story_clock_before is the announce time (pre-decide).
        final before = deleted.activeMetadata?['story_clock_before'] as String?;
        if (_clockRunning && StoryClock.parse(before) != null) {
          _timeService.restoreTimeFromRealismState({'storyClock': before});
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

  /// Timeline-integrity invalidation (Journal + Growth twin, audit P1.9):
  /// content at [position] was rewritten — regen, swipe, edit, or delete.
  /// Cards/rings citing positions ≥ [position] describe events that no longer
  /// happened, so they are removed. Pass cursors roll back when the rewrite
  /// sits inside the consumed window so the next pass re-reads it.
  ///
  /// Item-memory cards are written deterministically from pocket ops and
  /// cite the reply position WITHOUT advancing [_summaryLastIndex], so the
  /// old early-return (`position >= cursor`) left them as phantoms on every
  /// regen/delete of a fresh turn (release audit 2026-08-11). Card purge
  /// therefore always runs; cursor rollback stays gated.
  ///
  /// Recap ("Where we are") is CLEARED on rewrite (M3, 2026-08-11): it is a
  /// free-form paragraph with no per-line receipt, so it cannot be surgically
  /// rewound. Leaving it would assert discarded plot as "earlier in this
  /// story." Empty is honest; [buildRecapBlock] injects nothing; the next
  /// maintenance pass (kicked below) refills it from the new timeline.
  void _invalidateJournalFrom(int position) {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    _journalReview.abandon();
    _growthReview.abandon();
    if (position < _summaryLastIndex) {
      _summaryLastIndex = position;
    }

    // Clear stale recap before the next generation can re-inject it.
    var recapCleared = false;
    if (_summary.isNotEmpty) {
      _summary = '';
      recapCleared = true;
      debugPrint(
        '[Journal] Timeline rewrite at $position — cleared stale recap '
        '(refill on next journal pass)',
      );
    }

    // Fire-and-forget BUT error-contained: this select+delete chain can
    // outlive the service (delete a message, then close the app — or a test
    // teardown closing the Drift isolate), and an unhandled "Channel was
    // closed" from the zone is exactly how ec82f27's H3 guard went red on CI
    // while every assertion in it passed. Same containment contract as
    // _doSaveChat: log, never crash the zone; nothing could retry anyway.
    unawaited(
      _journalStore
          .invalidateCardsCitingFrom(sessionId, position)
          .then((removed) {
            if (_disposed) return;
            // Kick whether cards or only recap moved — both need a refill.
            if (removed > 0 || recapCleared) {
              _journalMaintenance.eventKickPending = true;
            }
            if (removed > 0) {
              debugPrint(
                '[Journal] Timeline rewrite at $position — removed $removed '
                'card(s) citing the discarded region',
              );
            }
            if (removed > 0 || recapCleared) notifyListeners();
          })
          .catchError((Object e) {
            debugPrint(
              '[Journal] ⚠ card invalidation at $position skipped: $e',
            );
            // Recap already cleared synchronously; still ask for a refill.
            if (!_disposed && recapCleared) {
              _journalMaintenance.eventKickPending = true;
              notifyListeners();
            }
          }),
    );

    // Growth twin: same rewrite must not leave discarded-plot rings injecting
    // as personality, or a stuck cursor that never re-scores the tip.
    unawaited(_invalidateGrowthFrom(sessionId, position));

    // RAG twin (release audit 2026-08-15): the embedded message-window corpus
    // cites the same positions and had NO invalidation at all.
    unawaited(_invalidateEmbeddingsFrom(sessionId, position));

    // Recap clear is sync — notify even if the card future is still pending
    // so the sidebar "Where we are" empties immediately.
    if (recapCleared) {
      _journalMaintenance.eventKickPending = true;
      notifyListeners();
    }
  }

  /// Growth half of timeline integrity (audit P1.9). Journal twin: purge rings
  /// citing the rewritten region; roll the growth cursor back when needed.
  Future<void> _invalidateGrowthFrom(String sessionId, int position) async {
    try {
      final cursor = await _growthStore.cursorFor(sessionId);
      if (position < cursor) {
        await _growthStore.setCursor(sessionId, position);
        debugPrint(
          '[Growth] Timeline rewrite at $position — cursor rolled back '
          'from $cursor',
        );
      }
      final removed = await _growthStore.invalidateRingsCitingFrom(
        sessionId,
        position,
      );
      if (_disposed) return;
      if (removed > 0) {
        debugPrint(
          '[Growth] Timeline rewrite at $position — removed $removed '
          'ring(s) citing the discarded region',
        );
        // Rebuild cache — a bare invalidate() left injection empty until
        // reload. Journal twin re-reads the DB; Growth cannot.
        //
        // Through the CANONICAL builder, not a hand-rolled id list: refresh()
        // clears the cache and repopulates only the ids it is handed while
        // marking it valid, so the copy here (which forgot Scene Guests) made
        // a guest's rings read as "none" — silently dropping their growth from
        // the injection after any regen/edit/delete that purged a ring.
        await _refreshGrowthCache();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Growth] ⚠ ring invalidation at $position skipped: $e');
    }
  }

  /// RAG half of timeline integrity (Journal/Growth twin). Drops every stored
  /// message-window embedding whose window reaches [position] or later.
  ///
  /// Two failures, one delete. The window's stored `content` is the text as it
  /// was BEFORE the rewrite, and [MemoryService]'s dedupe is purely positional
  /// — a window whose range already exists is skipped forever — so the
  /// discarded/edited reply stayed retrievable and got injected 20+ turns
  /// later as a remembered-from-earlier line. And
  /// after a DELETE every later window's (start,end) addresses different
  /// messages, which mis-stamps story days and mis-aligns the journal de-dupe.
  /// Removing the rows is what lets `_maybeEmbedMessages` rebuild them from
  /// the live timeline on the next turn.
  ///
  /// Runs regardless of the RAG switch: rows written while it was on must not
  /// survive a rewrite just because it is off today. Same fire-and-forget,
  /// error-contained contract as the Journal/Growth invalidators.
  Future<void> _invalidateEmbeddingsFrom(String sessionId, int position) async {
    try {
      final removed = await _db.customUpdate(
        'DELETE FROM message_embeddings '
        'WHERE session_id = ? AND position_end >= ?',
        variables: [drift.Variable(sessionId), drift.Variable(position)],
        updates: {_db.messageEmbeddings},
      );
      if (removed > 0) {
        debugPrint(
          '[RAG] Timeline rewrite at $position — removed $removed embedded '
          'window(s) citing the discarded region',
        );
      }
    } catch (e) {
      debugPrint('[RAG] ⚠ embedding invalidation at $position skipped: $e');
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
