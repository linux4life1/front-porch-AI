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

/// The user-turn entry: [sendMessage] guards, persist, chaos wheel, and
/// call-model swap. Decay, generate handoff, director note, guest
/// chime-ins, and dream prefetch live on
/// `chat_service_send_handoff.dart`. Continue does not tick — that path
/// never enters this file.
extension ChatServiceSend on ChatService {
  /// [imageBytes] optionally attaches a photo (already downscaled+PNG-encoded
  /// by the composer) to this user turn. The bytes are saved to disk HERE,
  /// after all guards pass, so a guard bail can never orphan a file. The photo
  /// renders inline in the bubble, rides along as pixels on this turn's
  /// generation when the model can see (see [buildTurnImages]), and is
  /// described in the flattened history for later turns.
  Future<void> sendMessage(String text, {Uint8List? imageBytes}) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        (text.trim().isEmpty && imageBytes == null)) {
      return;
    }
    // Overlay / picker hydrate is still in flight. A send here would
    // persist the pre-hydrate realism reset onto whichever session is
    // currently live (often the last-active chat, not the one opening).
    if (_isLoadingSession) return;
    // Don't let a user turn start while forked-in entrances are still playing —
    // it would race the one-shot entrance directive / turn positioning.
    if (_entrancesInFlight) return;
    // Likewise, don't race an in-flight Scene Guest creation/entrance (the mint
    // runs a separate LLM call that doesn't set _isGenerating).
    if (_sceneGuest.busy) return;
    // A photo turn's captioning windows run while _isGenerating is false; this
    // guard stops a second send from interleaving them (see isPhotoTurnInFlight).
    if (_photoTurnInFlight) return;
    // Import clears `_messages` and remints the session. A Send during that
    // window appends into a list the import is about to throw away.
    if (_isImporting) return;
    // No new user turn while a generation is live (streaming, draining, or
    // finalizing). A send mid-turn interleaves this method's own message
    // inserts (dream block) with the active turn's writes on one shared
    // list — the 2026-07-28 dream-corruption report. Stop first: the Stop
    // button now halts a turn promptly (see the drain cancel fix).
    //
    // Deliberately _isGenerating, NOT _isTurnBusy. Extending this to the
    // post-generation window was tried twice and CI rejected it both times:
    // post-gen evals plus background objective checks meant the composer was
    // unavailable for most of a turn, and on a slow local backend a user
    // would meet a dead send button far more often than a live one.
    // Sending APPENDS a message; it does not shift indices or rewrite state
    // under a running eval the way delete/regenerate/swipe/cast do — those
    // keep the wider _isTurnBusy guard, because that is where the race
    // actually corrupts something.
    if (_isGenerating) return;
    final previousSend = _sendChain;
    final sendGate = Completer<void>();
    _sendChain = sendGate.future;
    try {
      await previousSend;
    } catch (_) {}
    if (_isGenerating) {
      sendGate.complete();
      return;
    }
    // A send that lands in the previous turn's SETTLING window must QUEUE
    // behind it, not race it: the new turn's pre-gen work (mood decay, needs
    // tick, the group per-speaker scalar re-point) otherwise runs before the
    // old turn's _saveScalarsIntoGroupRealism / snapshot restamp / chip
    // attach, cross-writing speaker A's realism state with speaker B's.
    // Bounded (15s deadline) and drains the save chain — the same
    // serialization point setActiveCharacter/setActiveGroup/loadSession
    // already use. The composer deliberately stays LIVE during settling
    // (greying it was rejected twice); this waits instead of refusing.
    // Also closes the _isPostGenerating latch: a turn started mid-settle
    // captured callerHeldSettling=true and wedged _isTurnBusy for the
    // session.
    try {
      if (_isPostGenerating) {
        _sendWaitingOnSettle = true;
        notifyListeners();
      }
      await _waitForTurnToSettle();
    } finally {
      if (_sendWaitingOnSettle) {
        _sendWaitingOnSettle = false;
        notifyListeners();
      }
      if (!sendGate.isCompleted) sendGate.complete();
    }
    if (_isGenerating) return;
    // [EvalTraffic]: whatever the fire-and-forget passes (journal, growth,
    // promises, cast…) spent since the last turn's print, reported now so
    // the turn's own line stays a clean measure of the turn.
    final backgroundTraffic = EvalTraffic.current.flushBackground();
    if (backgroundTraffic != null) debugPrint(backgroundTraffic);
    // One-shot absence acknowledgment: pending survives exactly the first
    // user turn after load (all of that turn's prompt builds see it); the
    // second turn clears it for good.
    if (_absenceAckPending) {
      if (_absenceAckConsumed) {
        _absenceAckPending = false;
      } else {
        _absenceAckConsumed = true;
      }
    }
    // Start-of-turn clear: cancelRealismEval only sets this while an eval is
    // live, and each turn's consumers clear it — but this guarantees a stray
    // set flag can never bleed into THIS turn and abort a reply the user did
    // not cancel.
    _realismEvalCancelled = false;
    clearSuggestions();
    // Before ANY prompt is built for this turn. Counting the greeting as
    // turn 0, this is what puts an authored wardrobe into turn 1's prompt —
    // the pass that used to do it runs after the reply exists, so the first
    // real answer was generated blind to what they were wearing.
    seedPocketsFromCards();
    // Hand-added item reactions the previous reply already played out are
    // done; ones still pending (never made it into a prompt) stay queued for
    // THIS turn. Cleared here, not at prompt build, so a regenerate of the
    // reacting reply reproduces the reaction.
    _dropConsumedItemIntros();

    // A new message while an /image prompt review is parked cancels it —
    // the desktop dialog is modal, but the web modal can be typed around.
    resolveImagePromptReview(null);

    // User is interacting — clear any pending auto-response state
    _pendingIdleCue = null;

    // ── Slash Command Handling (delegated to leaf) ──────────────────────
    // Skipped when a photo is attached: an attach makes the intent "send a
    // message" unambiguous, and consuming the text as a command would drop
    // the attachment silently.
    final trimmed = text.trim();
    if (imageBytes == null &&
        trimmed.startsWith('/') &&
        _characterRepository != null) {
      final handled = await _ensureCommandHandler().handle(trimmed);
      if (handled) return;
      // Unknown command — fall through and send as a normal message.
    }

    // In observer mode, route to sendDirectorNote instead
    if (_observerMode && _activeGroup != null) {
      await sendDirectorNote(text);
      return;
    }

    _toolProbe.beginUserSend();
    _webSearchService.beginUserSend();
    _wikiSearchService.beginUserSend();
    try {
      // Sending a real message ends the /exit undo window. A pending full-member
      // exit commits now (real removal + any collapse to a 1:1) so this turn runs
      // in the settled cast; lite-guest undo state is just cleared.
      await _commitPendingMemberExit();
      _clearExitUndo();

      // Save the attachment to disk only now that every guard has passed — the
      // composer passes bytes, not a path, so a guard bail above can't orphan a
      // file. Null when there are no bytes / the image service isn't wired.
      final imagePath = await _persistTurnImage(imageBytes);

      final senderName = _userPersonaService.persona.name;
      final userMsg = ChatMessage(
        text: text,
        sender: senderName,
        isUser: true,
        metadata: imagePath != null
            ? {'is_user_image': true, 'image_path': imagePath}
            : null,
      );
      // Session token for the caption writes below — captured NOW so a chat
      // switch anywhere during the (long) turn voids the stamp+save.
      final sessionToken = _currentSessionId;
      _messages.add(userMsg);
      await _saveChat();
      notifyListeners();

      // ── Dreams (Living Time §1) — a night passed, so the dream surfaces
      // before this morning's exchange. The text was PRE-GENERATED at the end
      // of the turn whose clock crossed the night (_maybeKickDreamPrefetch,
      // called from the post-generation phase), so this await is on an
      // almost-always-completed future and the send path no longer waits on a
      // model call (eval review item 6 — dreams were one of the two calls
      // still blocking a send). Owner rules, insertion position, the journal
      // card and the silent-skip floor are unchanged.
      //
      // The bookkeeping call here is anchor-only (nothing at entry consumes
      // pending any more): it runs BEFORE this turn's pre-generation clock
      // advance, so the first turn after a chat load anchors on the pre-advance
      // day exactly as the old design did. Without it the first post-generation
      // kick would anchor AFTER the advance and a night crossed on that very
      // first turn would be missed.
      _dreamService.checkRollover(
        sessionId: _currentSessionId,
        dayCount: _timeService.dayCount,
      );
      final parkedDream = _dreamService.takePrefetch(_currentSessionId);
      if (parkedDream != null) {
        try {
          final dream = await parkedDream.dream;
          if (_sceneChanged(sessionToken)) return;
          if (dream != null) {
            _messages.insert(
              _messages.length - 1,
              ChatMessage(
                text: dream,
                sender: parkedDream.ownerName,
                isUser: false,
                characterId: parkedDream.ownerCharacterId,
                metadata: {'is_dream': true},
              ),
            );
            notifyListeners();
            await _journalStore.addCard(
              sessionId: sessionToken!,
              characterId: parkedDream.ownerId,
              content: dream,
              category: 'moment',
              kind: 'dream',
              emotionLabel: _characterEmotion.isEmpty
                  ? null
                  : _characterEmotion,
              storyDay: _timeService.dayCount,
              storyClock: _timeService.storyClockIso,
              maxCards: _storageService.memorySettings.journalMaxCards,
            );
            await _saveChat();
          }
        } catch (e) {
          debugPrint('[Dreams] skipped: $e');
        }
      }

      // ── Blind-model photo fallback: caption BEFORE generating ───────────────
      // Vision-capable models return true immediately (their pixels ride along
      // and their caption runs post-turn); blind models run the offline
      // captioner so this turn's history already carries the gist. Returns false
      // when the scene changed during the (multi-second) caption await — abort
      // rather than run decay/realism/generation against a newly loaded chat.
      if (imagePath != null) {
        final stillHere = await runBlindPhotoCaption(
          userMsg,
          imagePath,
          sessionToken,
        );
        if (!stillHere) return;
      }

      // Reset the idle timer — user is interacting
      _cancelIdleTimer();

      // Clear the new chat flag after first user message to allow memory retrieval
      if (_isNewChat) {
        _isNewChat = false;
        debugPrint('[sendMessage] Cleared new chat flag, memories now allowed');
      }

      // {{idle_duration}} clock: the user just spoke.
      _lastUserMessageAt = DateTime.now();

      // Scan for lore keywords (thin to scanner; the user message is already
      // in _messages, so the scanner windows over recent history from there).
      _lorebookScanner.scanLatest();

      // ── Clear consumed chaos event from the previous turn ───────────────
      // Only clear if the event was already delivered in a response.
      // This preserves manual-spin events that haven't been used yet.
      // Delegated to service (core state moved).
      _chaosModeService.clearDeliveredPendingIfAny();
      // Clear Mafia force-ack only after a prior turn *showed* it and the user
      // is now continuing (regen of that AI reply still re-injects until here).
      unawaited(_porchMemoryImport.clearAfterAcceptedUserTurn());

      // ── OOC Time-Skip Detection ───────────────────────────────────────────
      // The standalone clock is added as a second driver rather than folding
      // both into _clockRunning: that getter is broader than the old condition
      // (it stays true in Director mode and during AFK), so using it here would
      // silently start honouring "(OOC: skip to morning)" in engine-ON states
      // that ignore it today. Additive only — every case that worked still
      // works, plus the one the user asked for.
      if (_realismActiveThisMode || _standaloneClockActive) {
        final before = _timeService.clock;
        await _timeService.detectOocTimeSkip(text);
        final after = _timeService.clock;
        if (after != before &&
            isNightSkip(stripQuotedSpeech(text).toLowerCase())) {
          _applyNightSkipRestore();
        }
        await _maybeMintEpisodeCrumbs(before, after);
      }

      // ── Direct-address turn routing (both cast surfaces) ─────────────────
      // 1:1: "@Evelyn …" anywhere (or a vocative — "Evelyn - can you clarify…")
      // routes this turn to the GUEST via the parity-safe guest path; the host
      // turn and its prep below (chaos tick/wheel, decay, pre-gen eval) are
      // skipped — guests carry ZERO Realism/Needs, the host simply didn't take
      // a turn. Fixes the "responds twice per message" Discord report
      // (2026-07-28). Group: "@Member" forces that member as this turn's
      // speaker (inside the call; returns null — the turn proceeds normally).
      // Decision logic lives in the scene-guest leaf.
      final addressedGuest = _directAddressRoutedGuest(userMsg.promptText);

      // ── Chaos Mode: check + pause for wheel if triggered ─────────────────
      // Guard + tick delegated (pendingInjection check via service getter).
      if (addressedGuest == null &&
          _chaosModeService.chaosModeEnabled &&
          _chaosModeService.pendingChaosInjection == null) {
        if (checkAndTickChaosPressure()) {
          // Create a completer so sendMessage pauses here until the wheel resolves
          _chanceTimeCompleter = Completer<void>();
          _chanceTimePendingTrigger = true;
          // Pre-pick the one event the web/mobile reveal modal shows + accepts
          // (the desktop spins its own wheel instead — same pool, same accept).
          final webWheel = _chaosModeService.spinWheelEvents();
          _webChanceTimeEvent = webWheel.isNotEmpty
              ? webWheel.first
              : 'Fate intervenes in an unexpected way.';
          notifyListeners(); // UI observes this to show the wheel
          // Wait for the user to spin + accept fate (completes in applyChanceTimeResult)
          await _chanceTimeCompleter!.future;
          _chanceTimeCompleter = null;
          _webChanceTimeEvent = null;
        }
      }

      // Note: depth decrement happens after AI response completes (see _generateResponse finalization).
      // This ensures lore triggered by the user message is visible in the current turn's prompt.

      // Voice call safe speed lane: swap to the fast call model BEFORE the
      // pre-generation work below, so the objective check, the realism judges
      // and the standalone clock all answer on it — not just the reply. The
      // helper self-gates (call mode + remote + a call model picked); guests
      // are excluded because a routed guest turn skips the host prep entirely.
      // The request phase adopts the swap into the turn's restore machinery;
      // the cancel return below and the callMode setter release an orphaned one.
      if (addressedGuest == null) _enterCallEvalModelSwap();

      // Check objective task completion BEFORE generating response
      // so the AI gets the updated task in its prompt
      await _maybeCheckTaskCompletionSync();

      await _sendDecayAndGenerate(
        addressedGuest: addressedGuest,
        userMsg: userMsg,
        imagePath: imagePath,
        sessionToken: sessionToken,
      );
    } finally {
      _toolProbe.endUserSend(_evalBackendIdentity);
    }
  }
}
