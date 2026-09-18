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

/// Message reprocess / revert / regenerate flows — manualReprocessNeeds,
/// revertNeedsReprocess, regenerateLastMessage. These replay a turn with the
/// per-speaker realism dance (load → re-eval → save) and the time-travel
/// realism rollback. Extracted verbatim from `chat_service.dart` (zero behaviour
/// change) to shrink the god file; as `part of` it reaches the private services,
/// messages, and dance helpers exactly as before.

extension ChatServiceReprocess on ChatService {
  /// Which cast member said [msg]. See [resolveGroupSpeakerForMessage].
  CharacterCard? _resolveGroupSpeakerForMessage(ChatMessage msg) =>
      resolveGroupSpeakerForMessage(_groupCharacters, msg);

  /// Regenerate the main character's (host's) most recent message when it has
  /// been buried under Scene Guest (Lite NPC) chime-in replies — the case the
  /// last-message-only [regenerateLastMessage] button can no longer reach (the
  /// guest spoke last). The guest replies were reactions to the host text we are
  /// about to discard, so they are removed from the chat (UI + context) first;
  /// the host message is then regenerated as a new swipe via
  /// [regenerateLastMessage] (so realism is reverted to the previous accepted
  /// baseline exactly as for a normal regen — no parallel logic); finally the
  /// guest chime gate is re-run against the NEW host reply, so a guest speaks
  /// again only if it is still warranted (mention / relevance), never blindly.
  ///
  /// When the host message is already last (no trailing guests) this simply
  /// delegates to [regenerateLastMessage].
  Future<void> regenerateMainCharacter({String? critique}) async {
    if (_messages.isEmpty || _sceneGuest.busy) return;
    if (!await _yieldSettlingTurn()) return;
    _memoryPassEpoch++;
    // Backend gate BEFORE any guest-tail splice — same restore problem as
    // regenerateLastMessage (see _abortIfBackendDown).
    if (await _abortIfBackendDown()) return;

    // Walk back past the trailing guest replies to the host message beneath them.
    int hostIndex = -1;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') {
        return; // user/System tail — nothing to regen
      }
      // Narration banners (dreams, Chance Time) look like character messages
      // (isUser false, character-name sender) but are not regen targets —
      // regenerating one would replace a rollover artifact with a chat reply.
      if (m.activeMetadata?['is_dream'] == true ||
          m.activeMetadata?['is_chance_time_narration'] == true) {
        return;
      }
      if (!_isGuestAuthoredMessage(m)) {
        hostIndex = i;
        break;
      }
    }
    if (hostIndex < 0) return; // only guest messages present — no host to regen

    // Host already last → plain regen (no guests to pop).
    if (hostIndex == _messages.length - 1) {
      await regenerateLastMessage(critique: critique);
      return;
    }

    // Reconstruct the user text that prompted the host turn for the re-chime gate.
    String userText = '';
    for (int i = hostIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        userText = _messages[i].text;
        break;
      }
    }

    // Remove the now-stale trailing guest replies from UI + context, then regen
    // the (now last) host message and re-run the chime gate on the new reply.
    _messages.removeRange(hostIndex + 1, _messages.length);
    await _saveChat(replaceAll: true);
    notifyListeners();
    await regenerateLastMessage(critique: critique);
    await _maybeRunSceneGuestChimeIns(userText: userText);
  }

  Future<void> regenerateLastMessage({String? critique}) async {
    if (_messages.isEmpty || _sceneGuest.busy) return;
    if (!await _yieldSettlingTurn()) return;
    _memoryPassEpoch++;
    // Hold the settling flag across the WHOLE regen — the realism revert +
    // eval replay before generation and the swipe-merge after it both run
    // outside _generateResponse, and used to run with every guard open: a
    // send/delete/chat-switch landing there operated on a timeline with the
    // last message popped or the merge half-done (the same interleave class
    // the in-generate settling fix closed). _generateResponse restores the
    // caller's hold on exit instead of hard-clearing, so this survives the
    // nested call; the finally makes a wedged flag impossible. The body is
    // extracted (not inlined in the try) purely so its early returns and
    // this hold compose without re-indenting the whole flow.
    _isPostGenerating = true;
    try {
      await _regenerateLastMessageHeld(critique: critique);
    } finally {
      _isPostGenerating = false;
    }
  }

  Future<void> _regenerateLastMessageHeld({String? critique}) async {
    // Backend gate BEFORE the pop below — aborting after removeLast would
    // drop the popped reply (the deep guard in _generateResponse cannot
    // restore it; see _abortIfBackendDown).
    if (await _abortIfBackendDown()) return;

    // A failed turn leaves `user -> System(error banner)`, and that matched
    // NEITHER branch below: not a character message (the first), not a user
    // message (the second). So regenerate was a silent no-op after any failed
    // generation, and the only recovery a user could find was to copy their
    // own text out, delete the message, and retype it.
    //
    // Drop the banner when a USER turn is sitting directly behind it — the
    // "last message is a user turn" branch below then regenerates from that
    // prompt, which is precisely the intent. The test is structural rather
    // than tagged by producer because that is what makes it safe: all three
    // System banners (generation error, backend-down, failed entrance) are
    // only discardable when there is an unanswered user turn behind them. A
    // banner following a CHARACTER message is left alone.
    if (_messages.length >= 2 &&
        !_messages.last.isUser &&
        _messages.last.sender == 'System' &&
        _messages[_messages.length - 2].isUser) {
      _messages.removeLast();
      await _saveChat(replaceAll: true);
    }

    // Check if the last message is from the character. Narration banners
    // (dreams, Chance Time) carry a character-name sender but must never be
    // regen targets — a regen would swipe a chat reply into the banner.
    if (!_messages.last.isUser &&
        _messages.last.sender != 'System' &&
        _messages.last.activeMetadata?['is_dream'] != true &&
        _messages.last.activeMetadata?['is_chance_time_narration'] != true) {
      // New swipe; pop first so the cite is persist index, not window 23.
      final lastMsg = _messages.removeLast();
      // Is this a Scene Guest message? If so the whole regen must stay a
      // parity-safe GUEST turn: skip every Realism/Needs revert + re-eval below
      // and regenerate spoken as the guest (guestSpeaker), exactly like the
      // normal guest turn path. A host message keeps the existing behaviour.
      final regenGuest = _sceneGuestForMessage(lastMsg);
      // If the message was authored by a guest who has since LEFT the scene (or
      // had their card deleted), we can neither regenerate as them nor run the
      // host realism block on their text (that would perturb the host's
      // bond/trust/emotion/needs from guest-authored content). Refuse cleanly
      // BEFORE journal invalidation — the bubble stays on screen, so its
      // cites must stay too.
      if (regenGuest == null && _isGuestAuthoredMessage(lastMsg)) {
        _messages.add(lastMsg); // put it back untouched
        notifyListeners();
        _setGuestStatus(
          'Can’t regenerate "${lastMsg.sender}" — they have left the scene.',
          isError: true,
        );
        return;
      }
      _invalidateJournalFrom(
        persistMessagePosition(
          base: _history.basePosition,
          index: _messages.length,
        ),
      );
      // Snapshot the rejected swipe's metadata (e.g. manual needs reprocess) before
      // we add a new swipe — regen must not clobber prior swipe timelines.
      final rejectedSwipeIndex = lastMsg.swipeIndex;
      Map<String, dynamic>? preservedRejectedMeta;
      if (rejectedSwipeIndex >= 0) {
        if (rejectedSwipeIndex < lastMsg.swipeMetadata.length &&
            lastMsg.swipeMetadata[rejectedSwipeIndex] != null) {
          preservedRejectedMeta = Map<String, dynamic>.from(
            lastMsg.swipeMetadata[rejectedSwipeIndex]!,
          );
        } else if (lastMsg.activeMetadata != null) {
          preservedRejectedMeta = Map<String, dynamic>.from(
            lastMsg.activeMetadata!,
          );
        }
      }
      notifyListeners();

      // Resolve the rejected turn's speaker once (exact name match) — used to
      // force the turn manager AND to target the realism revert below. If the
      // member was renamed/removed, BOTH sites skip rather than fall back to
      // the first member: forcing or reverting the wrong character corrupts
      // that character's state and attribution.
      CharacterCard? regenSpeakerCard;
      String regenSpeakerSid = '';
      if (_activeGroup != null && regenGuest == null) {
        regenSpeakerCard = _resolveGroupSpeakerForMessage(lastMsg);
        if (regenSpeakerCard != null) {
          regenSpeakerSid = _getCharacterIdFromCard(regenSpeakerCard);
        }
      }

      // In group mode, force the turn manager to the *original* speaker of the
      // removed message before generation. This prevents regen from picking a
      // different character (the core of the "speaker changed after regen" bug).
      if (regenSpeakerCard != null) {
        _groupManager?.setNextSpeaker(regenSpeakerCard);
      }

      // Roll back objective mutations recorded for the rejected turn (eval
      // proposals + completion-check side effects) BEFORE the eval replay, so
      // the new turn re-derives objectives from a clean baseline instead of
      // stacking on the invalidated turn's (and dedup can't suppress a fresh
      // proposal because the rejected turn's copy still exists). Runs with or
      // without realism (completion checks also run realism-off); id-addressed
      // ops keep 1:1 and group identical. Guest turns never touch objectives.
      if (regenGuest == null) {
        await _revertObjectiveTurnOps(lastMsg);
        // Rewind the rejected turn's pockets ops to the pre-turn record, so
        // the regenerated reply's own pass re-applies from the same base
        // instead of stacking — "they hand you their keys", regenerate, they
        // keeps knitting, and the keys used to be gone anyway (hostile
        // review 2026-08-11). Group-safe: the stamp carries the speaker's
        // own charId. The journal invalidation above already took the
        // rejected turn's item cards with it.
        _restorePocketsFromStamp(lastMsg, after: false);
      }

      // Clock rewind for every driver (engine, standalone, Scene Guest).
      // The post-reply tick stamps story_clock_before; without this a
      // swipe would double-advance. Manual chevron/calendar nudges on
      // this bubble survive (same time_nudged flag as the engine path).
      final clockWasNudged =
          lastMsg.activeMetadata?['realism_state'] is Map &&
          (lastMsg.activeMetadata!['realism_state'] as Map)['time_nudged'] ==
              true;
      if (_clockRunning && !clockWasNudged) {
        final before = lastMsg.activeMetadata?['story_clock_before'] as String?;
        if (StoryClock.parse(before) != null) {
          _timeService.restoreTimeFromRealismState({'storyClock': before});
        }
      }

      _revertRegenRealismBaseline(
        lastMsg: lastMsg,
        regenGuest: regenGuest,
        regenSpeakerCard: regenSpeakerCard,
        regenSpeakerSid: regenSpeakerSid,
      );

      // 1:1 only: replay decay + the realism eval inline here (groups replay
      // via the per-speaker dance inside _generateResponse).
      if (_realismEnabled && _activeGroup == null && regenGuest == null) {
        // Set UI streaming state
        _isEvaluatingRealism = true;
        _realismEvalStreamText = '';
        notifyListeners();

        void handleChunk(String chunk) {
          _realismEvalStreamText += chunk;
          // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
          _evalChunkTimer?.cancel();
          _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
            try {
              notifyListeners();
            } catch (_) {
              // Widget was deactivated — timer fired after navigation
            }
          });
        }

        // Record the (restored) needs baseline as the pre-turn vector BEFORE
        // the decay tick below — sendMessage stamps pre-tick and the group
        // dance stamps preDecay, so a regen's chips must count the decay the
        // same way or they understate the turn by exactly the decay component
        // (and deleting the regenerated reply under-refunds by it — caught by
        // regen_chip_attach_test: the original showed a hygiene chip, the
        // regen didn't).
        if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
          _pendingRealismMetadata ??= {};
          _pendingRealismMetadata!['needs_pre_turn_vector'] =
              Map<String, int>.from(_needsSimulation.vector);
        }

        // Apply decay and cooldown — mirrors the normal path, which decays
        // AFTER capturing the baseline so the chips record decay + impact.
        _applyMoodDecay();
        _needsSimulation.tickDecay();
        _nsfwService.decrementCooldownIfActive();

        if (_oneShotActive) {
          await _evaluateOneShotCall(onChunk: handleChunk);
        } else {
          // Same batch-verify helper as the primary send path so regen
          // cannot drift (chips, fixation, autonomous objectives).
          await _runBatchedRealismVerification(
            () => _fireStaggeredRealismEvals(handleChunk),
          );
        }

        // Check for cancellation after evals complete
        if (_realismEvalCancelled) {
          debugPrint(
            '[Realism] Evaluation cancelled during regenerate, aborting',
          );
          // Put the popped reply back BEFORE bailing. The regen removed it at
          // the top so the outbound prompt wouldn't contain it, and
          // _generateResponse — the thing that appends the replacement — is
          // still below us. Returning without this destroys the message and
          // every swipe it carried. It is the same hazard the backend gate
          // further up already guards ("aborting after removeLast would drop
          // the popped reply"); the cancel path just never learned it.
          //
          // Putting the TEXT back is only half of it. Everything above already
          // un-applied the accepted turn — bond/trust/arousal reverted, needs
          // restored from needs_pre_turn_vector, the baseline pulled from the
          // PREVIOUS accepted message, the stance rewound, pockets rolled to
          // the pre-turn record — and then charged a fresh decay tick. Bailing
          // here without the same restore the two success paths run (see
          // `if (regenGuest == null) _restoreRealismStateForSpeaker(lastMsg)`
          // below) left the message displaying chips the sidebar and the
          // session row no longer agreed with, and `_saveChat()` persisted the
          // wrong scalars. 1:1-only branch, host-only (guests never get here).
          _messages.add(lastMsg);
          _restoreRealismStateForSpeaker(lastMsg);
          _restorePocketsFromStamp(lastMsg, after: true);
          _pendingRealismMetadata = null;
          _realismEvalCancelled = false;
          _evalChunkTimer?.cancel();
          _evalChunkTimer = null;
          _isEvaluatingRealism = false;
          notifyListeners();
          await _saveChat();
          return;
        }

        // Cancel any pending debounce notify before closing the overlay
        _evalChunkTimer?.cancel();
        _evalChunkTimer = null;
        _isEvaluatingRealism = false;
        notifyListeners();
      }

      // In group mode the per-speaker realism eval (and its metadata / needs deltas)
      // happens inside _generateResponse via _evaluateRealismForUpcomingSpeaker
      // for the correctly-forced speaker. Skip the 1:1 scalar synthesis here.
      Map<String, int>? regenPreTurn;
      if (_activeGroup == null && regenGuest == null) {
        // Save pre-turn vector BEFORE _generateResponse (which clears
        // _pendingRealismMetadata).
        regenPreTurn =
            _pendingRealismMetadata?['needs_pre_turn_vector']
                as Map<String, int>?;

        // Synthesize metadata after all regen evals complete — mirrors the
        // normal path (line 4020) so emotion_label and realism_state are in
        // _pendingRealismMetadata before _generateResponse consumes it.
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
        _pendingRealismMetadata!['realism_state'] = _captureRealismState(
          preTurn: regenPreTurn,
        );

        // If cancellation was requested during realism evaluation, abort
        // generation — restoring the popped reply first, for the same reason
        // as the cancel point above: _generateResponse has still not run, so
        // this local is the only place the message still exists.
        if (_realismEvalCancelled) {
          _messages.add(lastMsg);
          // Same put-back contract as the cancel point above: the message
          // returns WITH the state it was accepted under.
          _restoreRealismStateForSpeaker(lastMsg);
          _restorePocketsFromStamp(lastMsg, after: true);
          _pendingRealismMetadata = null;
          _realismEvalCancelled = false;
          notifyListeners();
          await _saveChat();
          return;
        }
      }

      // story_clock_before wins over previousSessionState. A guest (no
      // realism_state) can sit between two host lines; restoring the last
      // stamped host snapshot would rewind PAST that guest's decide.
      if (_clockRunning && !clockWasNudged) {
        final before = lastMsg.activeMetadata?['story_clock_before'] as String?;
        if (StoryClock.parse(before) != null) {
          _timeService.restoreTimeFromRealismState({'storyClock': before});
        }
      }

      // Invalidate ONNX cache for the new response (delegated)
      _expressionService.invalidateOnnxCacheForNewResponse();

      // Generate into a new message — it will be appended by _generateResponse.
      // For a guest message we pass guestSpeaker so the new swipe is spoken as
      // the guest and the entire Realism/Needs post-gen block is skipped (the
      // `guestSpeaker == null` guard). For a host message regenGuest is null and
      // this is the unchanged host path: _generateResponse runs the post-gen
      // needs checks AND the chip attach — a regen runs in normal mode, so
      // needs_deltas land on the streamed message exactly like a fresh turn
      // (1:1 and group alike) and ride newMetadata into the swipe-merge below.
      // The duplicate post-generation recompute that used to live here was a
      // second source of truth for the same numbers; deleted 2026-08-04.
      final preGenLen = _messages.length;
      await _generateResponse(
        GenerationMode.normal,
        directUserSend: true,
        guestSpeaker: regenGuest,
        forceSpeaker: regenGuest == null && _activeGroup != null
            ? _resolveGroupSpeakerForMessage(lastMsg)
            : null,
        regenCritique: RegenCritiqueInjection.fragment(
          spokenText: lastMsg.displayText,
          reason: critique ?? '',
        ),
      );

      // After generation, merge the new response as a swipe on the original
      // message — but ONLY when _generateResponse actually appended one. It
      // can return empty-handed (the group per-speaker realism cancel path
      // saves-and-returns before assembling blocks) or append a System error
      // banner (any phase-1..4 throw). The old guard read `_messages.last`
      // alone, so an empty return dropped the popped reply — with every
      // alternate swipe it held — forever (and in a group whose previous
      // entry was ANOTHER member's reply, it merged that member's message
      // into the regen target instead). The length check makes "no new
      // reply" restore the popped message at its original position.
      await _mergeOrRestoreRegenSwipe(
        lastMsg: lastMsg,
        regenGuest: regenGuest,
        preservedRejectedMeta: preservedRejectedMeta,
        rejectedSwipeIndex: rejectedSwipeIndex,
        preGenLen: preGenLen,
      );
    } else if (_messages.last.isUser) {
      // The last message is the user's prompt (e.g. the AI reply was deleted),
      // so there is no swipe to add — generate a fresh response from it.
      // 1:1 evals live in sendMessage, so this path does not re-tick needs.
      // Group evals live inside _generateResponse; skipSpeakerEval keeps
      // that dance from running a second time (Continue still LOADs).
      await _generateResponse(GenerationMode.normal, skipSpeakerEval: true);
    }
  }
}
