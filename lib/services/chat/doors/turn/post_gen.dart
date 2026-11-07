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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Phase 6 (final) of a turn: state reset, sanitizer, lorebook, first
/// save, the Scene-Guest clock, TTS, director auto-play, and the post-reply
/// clock decide. Realism/Needs bookkeeping and Journal/Growth live in
/// [PostGenPasses]; the fire-and-forget passes in [PostGenSide].
///
/// **This is the parity-critical file** — see CLAUDE.md "Chat contracts"
/// (Mouth speech, Continue, Clock) for what each step must keep.
class PostGen {
  PostGen(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => _e.progress;
  RealismGraph get _g => _d.doors.graph();
  EntryDoor get _entry => _d.doors.entry();
  SessionStore get _sessions => _d.doors.sessions();
  ControlsDoor get _controls => _d.doors.controls();
  CastDoor get _cast => _d.doors.cast();
  PromptAssembler get _prompts => _d.doors.prompts();
  ObjectivesDoor get _objectives => _d.doors.objectives();
  StorageService get _storageService => _d.services.storage;
  KoboldService get _koboldService => _d.services.kobold;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  TtsService? get _ttsService => _d.services.tts();

  GroupChat? get _activeGroup => _session.activeGroup;
  AutoChatBudget get _autoChatBudget => _entry.autoChat;
  bool _autoChatPausesAfter(ChatMessage reply) =>
      _entry.director.autoChatPausesAfter(reply);
  bool get _autoPlayActive => _entry.director.autoPlayActive;
  Future<void> _autoPlayNext() => _entry.director.autoPlayNext();
  bool get _callMode => _controls.callMode;
  bool get _clockRunning => _controls.clockRunning;
  StoryClockWriter get _clockWriter => _g.clockWriter;
  List<LoreEntryRef> _collectLoreRefs({bool? inheritOverride}) =>
      _g.lore.collectLoreRefs(inheritOverride: inheritOverride);
  EpisodeCrumbMinter get _episodeCrumbs => _g.episodeCrumbs;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool _isGuestAuthoredMessage(ChatMessage m) =>
      _cast.guests.isGuestAuthoredMessage(m);
  bool _isSeeded(GenTurn t) => _prompts.tokenAlts.isSeeded(t);
  LorebookScanner get _lorebookScanner => _g.lore.scanner;
  NeedsPass get _needsPass => _g.needsPass;
  bool get _observerMode => _entry.director.observerMode;
  RealismEvals get _realismEvals => _g.evals;
  RealismScope _realismScope() => _g.scope;
  Future<void> _saveChat({bool replaceAll = false}) =>
      _sessions.save(replaceAll: replaceAll);
  SceneGuestState get _sceneGuest => _cast.guests.state;
  void _stampTokenAlts(GenTurn t) => _prompts.tokenAlts.stamp(t);
  TimeService get _timeService => _g.time;

  Future<void> finalize(GenTurn t) async {
    // Speech stream is done (or empty). Drop the pin BEFORE post-eval
    // [openWorkerLane] or finalize deadlocks waiting on itself.
    _llmProvider?.endMouthSpeech();
    _p.isGenerating = false;
    // Leftover abort from a prior yield/regen hold must not skip THIS
    // turn's clock. A user abort during this finalize re-sets the flags.
    _e.stops.clearPostGenAbortFlags();
    // Settling starts the instant the last token lands — the finalization
    // below (sanitizer, lorebook, _saveChat, post-gen checks, chip attach)
    // is still the turn; the old late raise let a new turn interleave
    // (message_actions Windows CI). Restored in the outer finally.
    _p.isPostGenerating = true;
    _p.cancelRequested = false;
    _p.generationProgress = 0.0;
    _p.generationPhase = GenerationPhase.idle;
    _p.prefillStartTime = null;
    _p.prefillPromptTokens = 0;
    _p.generationStartTime = null;
    t.perfPoller?.cancel();
    t.perfPoller = null;

    // Fetch final perf stats from KoboldCPP for post-generation display
    if (t.isLocalBackend) {
      _koboldService.fetchPerf().then((perf) {
        if (perf != null) _p.lastPerfData = perf;
      });
    }

    if (t.epoch == _p.generationEpoch &&
        emptySpeechAfterPregen(
          accumulated: t.accumulatedResponse,
          isContinue: t.mode == GenerationMode.continue_ || _isSeeded(t),
        )) {
      debugPrint(
        '[GpuSwap] empty mouth stream after PRE-GEN attach — not success',
      );
      t.streamTarget.text = kEmptySpeechAfterPregenNotice;
      _p.tokenBroadcast.add('__ERROR__');
      _p.sentenceBroadcast.add('__DONE__');
      await _saveChat();
      _d.notify();
      return;
    }

    // Signal generation complete to SSE listeners
    _p.tokenBroadcast.add('__DONE__');

    // Flush remaining sentence buffer and signal done to sentence listeners
    if (_p.sentenceBuffer.trim().isNotEmpty) {
      _p.sentenceBroadcast.add(_p.sentenceBuffer.trim());
      _p.sentenceBuffer = '';
    }
    _p.sentenceBroadcast.add('__DONE__');

    _d.notify();

    // Only finalize if this generation is still current
    if (t.epoch == _p.generationEpoch) {
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
        newPart = stripEvalThinkBlocks(newPart);
      }

      // Close an open think on the PREFIX before glue — closing after
      // concat put Continue's new words inside the thought (empty bubble).
      final prefix = t.mode == GenerationMode.continue_
          ? closeOpenThink(t.continuePrefix)
          : '';
      String finalResponse = t.mode == GenerationMode.continue_
          ? glueContinueText(prefix, newPart)
          : (t.continuePrefix + newPart).trim(); // prefix: a rewrite's seed

      // Close a dangling think. Lift only a short closed think-only line.
      // A long reasoning dump stays tagged. An unclosed cut-off stays tagged.
      final mouthIn = finalResponse;
      finalResponse = resolveMouthSpeech(mouthIn);
      final mouthParts = splitMessageForEdit(closeOpenThink(mouthIn));
      if (mouthParts.body.trim().isEmpty &&
          mouthParts.thinking.trim().isNotEmpty) {
        final kept = finalResponse.toLowerCase().contains('<think>');
        debugPrint(
          kept
              ? '[Mouth] kept think-only dump '
                    '(${mouthParts.thinking.trim().length} chars)'
              : '[Mouth] lifted think-only (${finalResponse.length} chars)',
        );
      }

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
      _stampTokenAlts(t);

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
          _session.messages.isNotEmpty &&
          identical(_session.messages.last, t.streamTarget)) {
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
      if (!_e.entry.isLiteTurn(t)) {
        await _e.passes.run(t, newPart, finalResponse);
      }

      // Lite / Scene Guest: no Realism/Needs on the speaker. Group
      // soft roster members still get the glance-only withUser pass
      // so Away / With you can move. 1:1 guestSpeaker stays out of
      // Away rotation. The chat clock still hands off and stamps
      // time (soft slots stay empty — they have no Needs). The early
      // `_saveChat` above ran BEFORE this tick — persist the new clock,
      // glance bit, and rewind stamp or a reload loses them.
      if (_e.entry.isLiteTurn(t)) {
        final scored = t.mode == GenerationMode.continue_
            ? (_isGuestAuthoredMessage(t.streamTarget) ? '' : newPart.trim())
            : finalResponse;
        await _e.group.runLiteGroupGlancePass(t, scored);
        if (t.mode == GenerationMode.continue_ || !_clockRunning) {
          _timeService.clearBodyBeat();
        }
        // Same abort contract as the engine path: a rejected finalize
        // must not keep the tick, wear, chip, or save. Regen waits up
        // to 5s in `_yieldSettlingTurn` — without this gate the aborted
        // wear lands, then replay wears again.
        if (_p.postGenAbortRequested) {
          debugPrint(
            '[Clock] running=$_clockRunning '
            'source=${_timeService.clockGateSource} '
            'porchLife='
            '${_storageService.realismSettings.passageOfTimeDefault} '
            'reason=abort',
          );
          _clockWriter.abortSlotClockIfThisTurnTicked(
            () => t.streamTarget,
            isContinue: t.mode == GenerationMode.continue_,
          );
        } else {
          await maybeAdvanceStoryClockAfterReply(t);
          if (_p.postGenAbortRequested) {
            _clockWriter.abortSlotClockIfThisTurnTicked(
              () => t.streamTarget,
              isContinue: t.mode == GenerationMode.continue_,
            );
          } else {
            _needsPass.wearBodiesAfterClock(t.mode, t.streamTarget);
            _e.entry.tickRefractoryAfterClock(t);
            _e.side.maybeKickDreamPrefetch();
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
          _session.messages.contains(t.streamTarget)) {
        final lastMsg = t.streamTarget;
        final msgId = 'msg_${_session.messages.indexOf(t.streamTarget)}';
        _ttsService!.speak(
          lastMsg.displayText,
          voiceKey: ttsVoiceForMessage(
            lastMsg,
            groupCast: _activeGroup != null ? _groupCharacters : null,
            host: _session.activeCharacter,
            sceneGuests: _sceneGuest.cards,
          ),
          messageId: msgId,
        );
      }

      // Paused while this auto-chat turn was being written: it still counts.
      if (!_autoPlayActive &&
          _autoChatBudget.turnRunning &&
          !t.streamTarget.isUser) {
        _autoChatBudget.spendPaused();
      }
      // Auto-play: if director mode is active, queue the next character
      // (unless this reply spoke to the absent user, or spent the run).
      if (_autoPlayActive &&
          _observerMode &&
          _activeGroup != null &&
          !(!t.streamTarget.isUser && _autoChatPausesAfter(t.streamTarget))) {
        // If TTS is active, wait for it to finish before starting the delay.
        // A pause and resume inside the wait starts its own turn; this one's
        // wait then belongs to the old run and must not add a second.
        final run = _autoChatBudget.run;
        if (_ttsService != null && _ttsService!.isSpeaking) {
          _e.side.waitForTtsThenContinue(run);
        } else {
          final delayMs = (_entry.director.directorDelaySec * 1000).round();
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (_autoPlayActive &&
                !_p.isGenerating &&
                _autoChatBudget.run == run) {
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
  Future<void> maybeAdvanceStoryClockAfterReply(GenTurn t) async {
    // The planner's today line moves here (and a day that rolls retires it):
    // those writes belong to this reply and rewind with it.
    _objectives.turnOps.reply = t.streamTarget.isUser ? null : t.streamTarget;
    try {
      await _advanceStoryClockAfterReply(t);
    } finally {
      _objectives.turnOps.reply = null;
    }
  }

  Future<void> _advanceStoryClockAfterReply(GenTurn t) async {
    final porch = _storageService.realismSettings.passageOfTimeDefault;
    debugPrint(
      '[Clock] running=$_clockRunning '
      'source=${_timeService.clockGateSource} '
      'porchLife=$porch '
      'mode=${t.mode.name} abort=${_p.postGenAbortRequested}',
    );
    if (t.mode == GenerationMode.continue_) {
      // Continue does not add minutes. A named time in the new
      // text still stamps the slot — live-only leave swipe/load
      // on the old pair (C1 / K-A).
      if (_clockRunning) {
        final named = clockNamedInReply(
          t.streamTarget.text,
          _timeService.clock,
        );
        if (named != null) {
          await _timeService.applyReconciledClock(named);
          _clockWriter.writeSlotClock(
            t.streamTarget,
            kind: SlotClockWrite.tick,
          );
        }
      }
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
      _clockWriter.writeSlotClock(
        msg,
        kind: SlotClockWrite.beforeOnly,
        before:
            StoryClock.parse(
              knownStoryClockBefore(msg) ?? _timeService.storyClockIso,
            ) ??
            _timeService.clock,
      );
    }
    // "A week later, she…" in the reply's own narration: the judge below
    // reports the days, unless a skip (the user's line, a /narrate beat)
    // already owns this turn. Either one settles the scene after; no
    // bridge card.
    _timeService.takeReplySkipMinutes();
    // Fiction wins (K-A). A named wall-clock is the beat — do not
    // add the conversational floor on top (07:30 + 2 min = 07:32).
    final named = clockNamedInReply(msg.text, _timeService.clock);
    if (named == null) {
      await _realismEvals.evaluatePhysicalStateCall(
        timeOnly: true,
        skipTodayEval: _e.entry.isLiteTurn(t),
        // Director and AFK turns never move the scene (design §3): the
        // clock may still tick, but the model is not offered a move it
        // narrated on an autopilot turn, where the author is away from
        // the keyboard and cannot confirm one anyway.
        sceneMovesAllowed: !_e.entry.isLiteTurn(t) && !_observerMode,
      );
    } else {
      await _timeService.applyReconciledClock(named);
      // No eval consumed the skip's turn ownership; it must not suppress
      // the next turn's eval.
      _timeService.releaseSkipOwnership();
      // K-A: overwrite the slot's own before so the stored pair is
      // named/named (07:30/07:30). Clamp still holds. Continue
      // already stamps through writeSlotClock above.
      _clockWriter.writeSlotClock(msg, kind: SlotClockWrite.tick);
    }
    if (named == null && _e.entry.isLiteTurn(t) && _clockRunning) {
      _clockWriter.writeSlotClock(msg, kind: SlotClockWrite.tick);
    }
    if (_timeService.takeReplySkipMinutes() >= kLongSkipMinutes) {
      LongSkipSettle(_realismScope()).settle();
    }
    await _episodeCrumbs.maybeMint(before, _timeService.clock);
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
