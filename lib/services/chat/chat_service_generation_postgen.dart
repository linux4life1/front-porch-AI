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

/// Phase 6 (final) of `_generateResponse`: state reset, sanitizer, lorebook,
/// first save, Scene-Guest clock, TTS, and director auto-play.
/// Realism/Needs bookkeeping and Journal/Growth live in
/// chat_service_generation_postgen_engine.dart (same library).
///
/// **This is the parity-critical file** — see CLAUDE.md "Tracing
/// Realism/Needs/Group Post-Generation, Chips, Sidebar & Climax Checks",
/// which now names this file for the post-gen finalization step.
extension ChatServiceGenerationPostGen on ChatService {
  Future<void> _finalizeGenerationTurn(_GenTurn t) async {
    // Speech stream is done (or empty). Drop the pin BEFORE post-eval
    // [openWorkerLane] or finalize deadlocks waiting on itself.
    _llmProvider?.endMouthSpeech();
    _isGenerating = false;
    // Leftover abort from a prior yield/regen hold must not skip THIS
    // turn's clock. A user abort during this finalize re-sets the flags.
    _clearPostGenAbortFlags();
    // Settling starts the instant the last token lands — the finalization
    // below (sanitizer, lorebook, _saveChat, post-gen checks, chip attach)
    // is still the turn; the old late raise let a new turn interleave
    // (message_actions Windows CI). Restored in the outer finally.
    _isPostGenerating = true;
    _cancelRequested = false;
    _generationProgress = 0.0;
    _generationPhase = GenerationPhase.idle;
    _prefillStartTime = null;
    _prefillPromptTokens = 0;
    _generationStartTime = null;
    t.perfPoller?.cancel();
    t.perfPoller = null;

    // Fetch final perf stats from KoboldCPP for post-generation display
    if (t.isLocalBackend) {
      _koboldService.fetchPerf().then((perf) {
        if (perf != null) _lastPerfData = perf;
      });
    }

    if (t.epoch == _generationEpoch &&
        emptySpeechAfterPregen(
          accumulated: t.accumulatedResponse,
          isContinue: t.mode == GenerationMode.continue_,
        )) {
      debugPrint(
        '[GpuSwap] empty mouth stream after PRE-GEN attach — not success',
      );
      t.streamTarget.text = kEmptySpeechAfterPregenNotice;
      _tokenBroadcast.add('__ERROR__');
      _sentenceBroadcast.add('__DONE__');
      await _saveChat();
      notifyListeners();
      return;
    }

    // Signal generation complete to SSE listeners
    _tokenBroadcast.add('__DONE__');

    // Flush remaining sentence buffer and signal done to sentence listeners
    if (_sentenceBuffer.trim().isNotEmpty) {
      _sentenceBroadcast.add(_sentenceBuffer.trim());
      _sentenceBuffer = '';
    }
    _sentenceBroadcast.add('__DONE__');

    notifyListeners();

    // Only finalize if this generation is still current
    if (t.epoch == _generationEpoch) {
      // New tokens only from the stream. Continue paints
      // `glueContinueText(continuePrefix, tokens)` mid-stream; we must
      // re-merge the same way before write-back or sanitize, or the saved
      // bubble collapses to the continuation fragment (audit 2026-08-11 P0.1).
      String newPart = t.accumulatedResponse;

      // SillyTavern-like safety net for Continue (and call mode): even after
      // requesting enabled:false + max_tokens:0 + exclude:true on the
      // provider, some thinking models still emit stray <think> text. Strip
      // from the NEW portion only — never re-strip the pre-continue body.
      if (t.mode == GenerationMode.continue_ || _callMode) {
        newPart = _stripThinkBlocks(newPart);
      }

      // Close an open think on the PREFIX before glue — closing after
      // concat put Continue's new words inside the thought (empty bubble).
      final prefix = t.mode == GenerationMode.continue_
          ? closeOpenThink(t.continuePrefix)
          : '';
      String finalResponse = t.mode == GenerationMode.continue_
          ? glueContinueText(prefix, newPart)
          : newPart.trim();

      // Close a dangling think. Lift only a *closed* think-only body
      // (Qwen reasoning_content). An unclosed cut-off stays tagged.
      finalResponse = resolveMouthSpeech(finalResponse);

      // ── Output Sanitizer ──────────────────────────────────────────────
      // NOTE: This runs BEFORE _lorebookScanner.scanLatest() below, so
      // lorebook keyword triggers operate on the sanitized text. If a rule
      // replaces text that a lorebook keyword was matching, the trigger
      // would stop matching. This is intentional — sanitized output is the
      // "final" text that enters history and is scanned for lore.
      if (t.g2.resolveOutputSanitizerEnabled(_storageService)) {
        final rules = t.g2.resolveOutputSanitizerRules(_storageService);
        final sanitized = sanitizeOutput(finalResponse, rules);
        if (sanitized.trim().isEmpty && finalResponse.trim().isNotEmpty) {
          // A runaway rule ate the entire reply — keep the original text
          // rather than persisting an empty message the user can't recover.
          debugPrint(
            '[Sanitizer] rules reduced the whole reply to empty — '
            'keeping the unsanitized text.',
          );
        } else {
          finalResponse = sanitized;
        }
      }

      // Leftover [today: …] — strip so it never shows in the bubble.
      // Do not write todaySentence / abandonToday from the tag; the
      // scene-time eval owns that via TimeService.onTodayEval.
      final todayParsed = TodayLineTag.parse(finalResponse);
      finalResponse = todayParsed.visible;

      // Always persist the finalized body. Continue + strip without sanitizer
      // used to leave streamTarget alone after mutating only finalResponse —
      // and when sanitizer DID run it wrote new-tokens-only. One write-back.
      if (finalResponse.isNotEmpty || t.mode == GenerationMode.continue_) {
        t.streamTarget.text = finalResponse;
      }

      // Turn taken = durable, before lorebook/evals.
      await _saveChat();

      // Snapshot which entries were already triggered before scanning the AI response.
      // We will only decrement those — newly AI-triggered entries must keep their
      // full depth budget so they are visible on the next user turn.
      // Covers the full scanned universe (incl. group book + group worlds).
      final preAiTriggered = <LorebookEntry>{
        for (final ref in _collectLoreRefs(inheritOverride: true))
          if (ref.entry.isTriggered && !ref.entry.constant) ref.entry,
      };

      if (finalResponse.isNotEmpty &&
          _messages.isNotEmpty &&
          identical(_messages.last, t.streamTarget)) {
        // scanLatest reads the LAST message — only valid while the streamed
        // message still holds that position (a mid-turn insert/delete can
        // shift it; scanning someone else's text would trigger wrong lore).
        _lorebookScanner.scanLatest();
      }

      // Decrement only entries that were active before the AI response.
      // This preserves full depth for lore discovered in the AI's own words.
      // Thin delegation (preAi set computed in god for snapshot; scanner owns decrement).
      _lorebookScanner.decrementLoreDepthForEntries(preAiTriggered);

      // ── Scene Guest (Lite NPC) parity guard ──────────────────────────
      // A guest turn must NOT run the guest's own Realism Engine,
      // Needs scene eval, inter-character feelings, or the periodic
      // (facts/evolution/summary/RAG) evaluators. The guest carries
      // no such state. The chat clock is the exception — it is chat-
      // scoped and ticks after this guard so the next speaker is told
      // an honest time. Present full members wear that beat; the guest
      // themselves never invent a Needs map. Everything from here
      // through the periodic evals is gated so the guest's own state
      // stays empty. (Lorebook scan + _saveChat above still ran.)
      if (!_isLiteTurn(t)) {
        await _runPostGenEngineAndPeriodic(t, newPart, finalResponse);
      }

      // Lite / Scene Guest: no Realism/Needs on the speaker. Group
      // soft roster members still get the glance-only withUser pass
      // so Away / With you can move. 1:1 guestSpeaker stays out of
      // Away rotation. The chat clock still hands off and stamps
      // time (soft slots stay empty — they have no Needs). The early
      // `_saveChat` above ran BEFORE this tick — persist the new clock,
      // glance bit, and rewind stamp or a reload loses them.
      if (_isLiteTurn(t)) {
        final scored = t.mode == GenerationMode.continue_
            ? (_isGuestAuthoredMessage(t.streamTarget) ? '' : newPart.trim())
            : finalResponse;
        await _runLiteGroupGlancePass(t, scored);
        if (t.mode == GenerationMode.continue_ || !_clockRunning) {
          _timeService.clearBodyBeat();
        }
        // Same abort contract as the engine path: a rejected finalize
        // must not keep the tick, wear, chip, or save. Regen waits up
        // to 5s in `_yieldSettlingTurn` — without this gate the aborted
        // wear lands, then replay wears again.
        final clockBeforeIso = _timeService.storyClockIso;
        if (_postGenAbortRequested) {
          debugPrint(
            '[Clock] running=$_clockRunning '
            'source=${_timeService.clockGateSource} '
            'porchLife='
            '${_storageService.realismSettings.passageOfTimeDefault} '
            'reason=abort',
          );
        } else {
          await _maybeAdvanceStoryClockAfterReply(t);
          if (_postGenAbortRequested &&
              _timeService.storyClockIso != clockBeforeIso) {
            _timeService.restoreAbortedTick(clockBeforeIso);
          } else if (!_postGenAbortRequested) {
            _wearBodiesAfterClock(t);
            _stampTimePassedChip(t.streamTarget);
            _maybeKickDreamPrefetch();
            await _saveChat();
          }
        }
      }

      // (Task completion check now runs pre-generation in sendMessage)

      // TTS auto-play: speak the new character message automatically
      if (_ttsService != null &&
          _storageService.ttsSettings.ttsEnabled &&
          _storageService.ttsSettings.ttsAutoPlay &&
          !t.streamTarget.isUser &&
          _messages.contains(t.streamTarget)) {
        final lastMsg = t.streamTarget;
        final msgId = 'msg_${_messages.indexOf(t.streamTarget)}';
        // Resolve per-character voice, falling back to global default
        String? voiceKey;
        if (_activeGroup != null) {
          final charMatch = _groupCharacters
              .where((c) => c.name == lastMsg.sender)
              .firstOrNull;
          voiceKey = charMatch?.ttsVoice;
        } else {
          voiceKey = _activeCharacter?.ttsVoice;
        }
        _ttsService!.speak(
          lastMsg.displayText,
          voiceKey: voiceKey,
          messageId: msgId,
        );
      }

      // Auto-play: if director mode is active, queue the next character
      if (_autoPlayActive && _observerMode && _activeGroup != null) {
        // If TTS is active, wait for it to finish before starting the delay
        if (_ttsService != null && _ttsService!.isSpeaking) {
          _waitForTtsThenContinue();
        } else {
          final delayMs = (directorDelaySec * 1000).round();
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (_autoPlayActive && !_isGenerating) {
              _autoPlayNext();
            }
          });
        }
      }
    }

    // Restore original model if swapped for call mode
    if (t.originalModelName != null && _llmProvider != null) {
      _llmProvider!.openRouterService.configure(modelName: t.originalModelName);
    }
  }

  /// Post-reply clock decide. Announced time was already in the prompt;
  /// this sets what the NEXT speaker is told. Continue is the same beat.
  /// Scene Guests carry no Realism/Needs but the clock is chat-scoped, so
  /// they tick time-only (no Today rewrite).
  Future<void> _maybeAdvanceStoryClockAfterReply(_GenTurn t) async {
    final porch = _storageService.realismSettings.passageOfTimeDefault;
    debugPrint(
      '[Clock] running=$_clockRunning '
      'source=${_timeService.clockGateSource} '
      'porchLife=$porch '
      'mode=${t.mode.name} abort=$_postGenAbortRequested',
    );
    if (t.mode == GenerationMode.continue_) {
      debugPrint(
        '[Clock] return reason=continue source=${_timeService.clockGateSource}',
      );
      return;
    }
    if (!_clockRunning) {
      debugPrint(
        '[Clock] return reason=porch_life_off '
        'source=porch_life porchLife=$porch',
      );
      return;
    }
    final before = _timeService.clock;
    final msg = t.streamTarget;
    if (!msg.isUser) {
      // Stamp the LIVE swipe map. Writing `metadata` is a no-op for
      // regen when swipeMetadata[i] is already set — activeMetadata
      // returns that slot, not the legacy field.
      persistStoryClockBefore(
        msg,
        knownStoryClockBefore(msg) ?? _timeService.storyClockIso,
      );
    }
    await _realismEvals.evaluatePhysicalStateCall(
      timeOnly: true,
      skipTodayEval: _isLiteTurn(t),
    );
    if (_isLiteTurn(t)) {
      final named = clockNamedInReply(msg.text, _timeService.clock);
      if (named != null) await _timeService.applyReconciledClock(named);
    }
    _stampStoryClockAfter(msg);
    await _maybeMintEpisodeCrumbs(before, _timeService.clock);
    debugPrint(
      '[Clock] running=$_clockRunning '
      'source=${_timeService.clockGateSource} '
      'porchLife=$porch '
      'minutes=${_timeService.clock.difference(before).inMinutes} '
      'stamped=${_timeService.bodyTimeLabel} '
      'slot=${t.streamTarget.swipeIndex}',
    );
  }
}
