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
      // A guest turn must NOT touch the active character's Realism Engine,
      // Needs simulation, inter-character feelings, chips, or the
      // periodic (facts/evolution/summary/RAG) evaluators. The guest carries
      // no such state. The chat clock is the exception — it is chat-scoped
      // and ticks after this guard so the next speaker is told an honest
      // time. Everything from here through the periodic evals is
      // gated so guest presence/turns leave the primary's state untouched.
      // (Lorebook scan + _saveChat above still ran for the guest.)
      if (t.guestSpeaker == null) {
        await _runPostGenEngineAndPeriodic(t, newPart, finalResponse);
      }

      // Scene Guest: no Realism/Needs, but the chat clock still hands off
      // to whoever speaks next (host or another guest). The early
      // `_saveChat` above ran BEFORE this tick — persist the new clock
      // and the rewind stamp or a reload / guest-regen loses them.
      if (t.guestSpeaker != null) {
        await _maybeAdvanceStoryClockAfterReply(t);
        _maybeKickDreamPrefetch();
        await _saveChat();
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
}
