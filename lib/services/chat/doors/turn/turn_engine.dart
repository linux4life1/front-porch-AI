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
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

import 'greeting_eval_gate.dart';
import 'post_gen.dart';
import 'post_gen_group.dart';
import 'post_gen_passes.dart';
import 'post_gen_side.dart';
import 'promise_ledger.dart';
import 'regen_replay.dart';
import 'turn_deps.dart';
import 'turn_entry.dart';
import 'turn_progress.dart';
import 'turn_stops.dart';
import 'turn_stream.dart';

export 'turn_progress.dart';
export 'turn_deps.dart';
export 'turn_entry.dart';
export 'turn_stream.dart';
export 'turn_stops.dart';
export 'post_gen.dart';
export 'post_gen_passes.dart';
export 'post_gen_group.dart';
export 'post_gen_side.dart';
export 'regen_replay.dart';
export 'promise_ledger.dart';
export 'greeting_eval_gate.dart';

/// File scope, as it always was: one epoch for the process.
int _memoryPassEpoch = 0;

/// Runs one generation: admission ([TurnEntry]), the speaker pick and the
/// group dance, the prompt assembler's four phases, the stream
/// ([TurnStream]), post-generation ([PostGen], [PostGenPasses],
/// [PostGenSide]) and the stops ([TurnStops]). [progress] owns the turn's
/// flags and the status bar's numbers; the regen judge replay
/// ([RegenReplay]), the promise ledger ([PromiseLedger]) and the greeting
/// eval's stale guard ([GreetingEvalGate]) hang off it too.
///
/// Every phase body is the code the generation parts held, moved verbatim
/// with the carrier names of [GenTurn]. See docs/design/god-file-elimination.md
/// for the hazard list (H1 to H12) before touching a phase boundary.
///
/// Not a notifier: every transition calls the service's own notify
/// ([TurnDeps.notify]) at the moment the parts it replaces did.
class TurnEngine {
  TurnEngine(this.deps);

  final TurnDeps deps;

  late final TurnProgress progress = TurnProgress(
    deps.notify,
    busyElsewhere: () =>
        deps.doors.importer().isImporting ||
        deps.doors.cast().narrating ||
        deps.doors.send().gates.skipAsked,
  );
  late final TurnEntry entry = TurnEntry(this);
  late final TurnStream stream = TurnStream(this);
  late final TurnStops stops = TurnStops(this);
  late final PostGen postGen = PostGen(this);
  late final PostGenPasses passes = PostGenPasses(this);
  late final PostGenGroup group = PostGenGroup(this);
  late final PostGenSide side = PostGenSide(this);
  late final RegenReplay replay = RegenReplay(this);
  late final PromiseLedger promises = PromiseLedger(this);
  final GreetingEvalGate greetingEval = const GreetingEvalGate();

  /// A reply, its post-gen settle, an import or narration is running (see
  /// [TurnProgress.isTurnBusy]).
  bool get isTurnBusy => progress.isTurnBusy;

  /// Bumped on regen / settling abort so a fire-and-forget Journal or Growth
  /// pass started against the rejected window cannot apply (or fall through
  /// to XML) after abortGeneration tore the tools call down.
  int get memoryPassEpoch => _memoryPassEpoch;
  void bumpMemoryEpoch() => _memoryPassEpoch++;

  /// Waits until the turn in motion, its post-gen settle included, is done
  /// (the entry door's loading cover owns the wait).
  Future<void> waitForTurnToSettle() =>
      deps.doors.entry().cover.waitForTurnToSettle();

  TurnDeps get _d => deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => progress;
  RealismGraph get _g => _d.doors.graph();
  EntryDoor get _entry => _d.doors.entry();
  SessionStore get _sessions => _d.doors.sessions();
  ControlsDoor get _controls => _d.doors.controls();
  CastDoor get _cast => _d.doors.cast();
  PromptAssembler get _prompts => _d.doors.prompts();
  MediaDoor get _media => _d.doors.media();
  SendSpine get _send => _d.doors.send();
  StorageService get _storageService => _d.services.storage;
  UserPersonaService get _userPersonaService => _d.services.personas;
  KoboldService get _koboldService => _d.services.kobold;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  String _getCharacterIdFromCard(CharacterCard card) =>
      _session.characterIdFor(card);

  GroupChat? get _activeGroup => _session.activeGroup;
  AwayPulseState get _awayPulse => _cast.away.state;
  StoryClockReader get _clockReader => _g.clockReader;
  bool get _clockRunning => _controls.clockRunning;
  StoryClockWriter get _clockWriter => _g.clockWriter;
  bool get _directing => _entry.director.directing;
  GroupRealismStore get _groupStore => _g.groups;
  set _isCancellingRealismEval(bool v) => _g.evalStatus.cancelling = v;
  NeedsSimulation get _needsSimulation => _g.needs;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      _g.registers.pending = v;
  bool get _realismActiveThisMode => _g.realismActiveThisMode;
  RealismDance get _realismDance => _g.dance;
  bool get _realismEvalCancelled => _g.evalStatus.cancelled;
  set _realismEvalCancelled(bool v) => _g.evalStatus.cancelled = v;
  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) => _cast.away.runAwayPulse(userText: userText, fromUserSend: fromUserSend);
  Future<void> _saveChat({bool replaceAll = false}) =>
      _sessions.save(replaceAll: replaceAll);
  ChatGenerationSettings get _sessionGenSettings => _sessions.genSettings;
  TimeService get _timeService => _g.time;

  Future<void> generate(
    GenerationMode mode, {
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
    bool autonomous = false,
    bool directUserSend = false,
    bool skipSpeakerEval = false,
    String regenCritique = '',
  }) async {
    final (forcedWeb, forcedWiki) = _media.takeForcedLookup();
    // Raise before the first await so an unawaited caller (AFK idle)
    // is visible to drain / isTurnBusy immediately. A refused turn is
    // lowered inside [TurnEntry.admitTurn].
    _p.isGenerating = true;
    _d.notify();
    final speakers = await entry.admitTurn(mode, guestSpeaker, forceSpeaker);
    if (speakers == null) return;
    guestSpeaker = speakers.guest;
    forceSpeaker = speakers.force;
    // regenerateLastMessage holds the settling flag; the finally restores it.
    final callerHeldSettling = _p.isPostGenerating;
    final epoch = ++_p.generationEpoch;
    _p.isGenerating = true;
    _p.generationProgress = 0.0;
    _p.tokensGenerated = 0;
    _p.maxTokens = _sessionGenSettings.resolveMaxLength(_storageService);
    _p.generationStartTime = DateTime.now();
    _p.generationPhase = GenerationPhase.preparing;
    _p.prefillStartTime = null;
    _p.lastPerfData = null;
    _p.sentenceBuffer = '';
    _d.notify();

    final t = GenTurn(
      mode: mode,
      guestSpeaker: guestSpeaker,
      epoch: epoch,
      autonomous: autonomous,
      directUserSend: directUserSend,
      forcedWebQuery: forcedWeb,
      forcedWikiQuery: forcedWiki,
    );
    t.regenCritique = regenCritique;

    try {
      final userName = _userPersonaService.persona.name;
      t.userName = userName;

      // Determine the speaking character first (needed for system prompt priority)
      CharacterCard speakingCharacter;
      if (guestSpeaker != null) {
        // Scene Guest (Lite NPC) turn — stays in 1:1 (_activeGroup remains null),
        // the guest speaks in its own bubble. Carries NO Realism/Needs work
        // (see the guestSpeaker == null guards in the post-gen block below).
        speakingCharacter = guestSpeaker;
      } else if (_activeGroup != null) {
        // Continue resolved forceSpeaker above (id-first, refuse on
        // duplicates). Regen already passes it. Fresh turns pick present.
        // Auto-play / trigger-next: quiet-pulse Away members on the N=3
        // cadence. User send already pulsed in send_handoff.
        if (mode == GenerationMode.normal &&
            !directUserSend &&
            forceSpeaker == null) {
          await _runAwayPulse(
            userText: _awayPulse.lastUserText,
            fromUserSend: false,
          );
        }
        if (forceSpeaker == null) {
          t.rotationBeforePick = _session.groupManager?.rotation;
        }
        speakingCharacter =
            forceSpeaker ?? _send.speakers.pickPresentGroupSpeaker();
      } else {
        speakingCharacter = _session.activeCharacter!;
      }
      t.speakingCharacter = speakingCharacter;

      if (guestSpeaker == null &&
          _activeGroup != null &&
          mode != GenerationMode.continue_ &&
          forceSpeaker == null &&
          AwayPulse.shouldWriteSkipBanner(
            speakerSkips: _send.speakers.groupSpeakerSkips(speakingCharacter),
            hasUnconsumedReturn: _awayPulse.pendingReturnSpeakId != null,
          )) {
        // Whole roster (or a forced @name) is Away / At work. Do not eat
        // the send: write a glance line. No reply to score, so the clock
        // takes the failure-drift step (bucket brigade still moves) and
        // Today is not rewritten.
        if (_clockRunning) {
          await _timeService.applyFailureDrift(
            minutes: directUserSend
                ? StoryClock.conversationalFloorMinutes
                : StoryClock.failureDriftMinutes,
          );
          // F3: persist the drift on the tip so reopen cannot rewind it.
          _clockWriter.writeSlotClock(
            _clockReader.visibleTipMessage(),
            kind: SlotClockWrite.tick,
          );
        }
        _session.messages.add(
          ChatMessage(
            text: _send.speakers.presenceSkipBanner(speakingCharacter),
            sender: 'System',
            isUser: false,
          ),
        );
        debugPrint(
          '[Presence] skip-turn ${speakingCharacter.name} — banner, no reply',
        );
        t.rotationBeforePick = null; // the skip is that member's turn
        _p.isGenerating = false;
        _p.generationPhase = GenerationPhase.idle;
        await _saveChat();
        _d.notify();
        return;
      }

      // Pin the realism speaker for the whole turn so prompt injection + decay
      // key on the character actually generating — not nextCharacter (the
      // *upcoming* speaker, null for random turn order). Soft group members
      // are pinned too: leaving them null made the fallback steal the next
      // full member's Needs/bond. 1:1 scene guests (guestSpeaker) stay null.
      // Cleared in the finally below. Lite turns still skip the realism
      // dance and the realism/objective prompt blocks.
      _groupStore.turnSpeakerId = (_activeGroup != null && guestSpeaker == null)
          ? _getCharacterIdFromCard(speakingCharacter)
          : null;

      // SINGLE realism eval path (group trigger). 1:1 evals live in sendMessage
      // so regen/generate does not re-score the host. Continue, and
      // user-last regen on a line from before per-speaker stamps, skip the
      // dance but still LOAD this speaker's scalars. A new group turn and a
      // stamped user-last regen (rewound first) dance. Guests carry no realism.
      if (guestSpeaker == null &&
          _activeGroup != null &&
          !entry.isLiteTurn(t) &&
          _realismActiveThisMode) {
        if (mode == GenerationMode.continue_ || skipSpeakerEval) {
          final sid = _getCharacterIdFromCard(speakingCharacter);
          if (sid.isNotEmpty) _realismDance.loadIntoScalars(sid);
        } else {
          await _realismDance.evaluateForUpcomingSpeaker(speakingCharacter);
          // Cancel-aborts-generation, group edition: consume the flag and
          // abort before any prompt is built. Entry-state flags are reset
          // by hand — the normal clears live in completion/catch.
          if (_realismEvalCancelled) {
            _clockReader.applyTipClock();
            _pendingRealismMetadata = null;
            _needsSimulation.consumePendingCatastrophe();
            _realismEvalCancelled = false;
            _p.isGenerating = false;
            _p.generationPhase = GenerationPhase.idle;
            _p.generationStartTime = null;
            await _saveChat();
            _d.notify();
            return;
          }
        }
      } else if (guestSpeaker == null && _directing && !entry.isLiteTurn(t)) {
        _realismDance.prepareDirectedSpeaker(
          speakingCharacter,
          stamp: mode != GenerationMode.continue_ && !skipSpeakerEval,
        );
      }

      // ── The six-phase turn pipeline: four prompt phases on the prompt
      // assembler (doors/turn/), then the stream and post-gen parts ──
      // Fixed order — `late` carrier fields make an out-of-order call a loud
      // LateInitializationError, not silent corruption.
      await _prompts.assembleBlocks(t);
      await _prompts.buildPlan(t);
      await _prompts.retrieveMemories(t);
      await _prompts.dispatch(t);
      if (await stream.consume(t)) {
        return; // user cancel: turn halted (H2)
      }
      await postGen.finalize(t);
    } catch (e) {
      _clockWriter.restoreCapturedThroughReader();
      // A stream that threw mid-think must not leave its live start behind.
      if (t.thinkStartedAt != null) t.sealThinkClock();
      final wasCancelled = _p.cancelRequested;
      _p.drainTimer?.cancel();
      _p.drainTimer = null;
      _p.tokenBuffer.clear();
      _p.isGenerating = false;
      _p.cancelRequested = false;
      _p.generationProgress = 0.0;
      _p.generationPhase = GenerationPhase.idle;
      _p.prefillStartTime = null;
      _p.prefillPromptTokens = 0;
      _p.generationStartTime = null;

      // "Connection closed before full header was received" is thrown by the http package
      // when the HTTP client is closed mid-stream (either by abortGeneration() or a process
      // crash/restart). Treat it the same as a user cancel — keep the partial response.
      final treatAsCancel = wasCancelled || looksLikeBackendUnreachable(e);

      // User-initiated cancel (or forced client close) — keep the partial response, no error message
      if (treatAsCancel) {
        // A think-start stamp means the reply was being painted: close its
        // thought like the stream-loop Stop does.
        await stops.haltStoppedTurn(
          t,
          t.thinkStartedAt != null ? t.streamTarget : null,
        );
        return;
      }

      // Build user-friendly error message (mapping lives in the pure leaf
      // generation_error_messages.dart, not a door — no chat service access).
      final errorMsg = friendlyGenerationError(e.toString());

      _session.messages.add(statusBannerMessage(errorMsg));

      // Signal error to SSE listeners
      _p.tokenBroadcast.add('__ERROR__');
      // '__ERROR__' is a TOKEN-stream sentinel only. The sentence stream must
      // still be told the turn is over — its consumer (call_overlay →
      // TtsService.speakStreaming) closes on '__DONE__' and on nothing else,
      // so without this a non-socket failure (OpenRouter 429/402/5xx, a
      // malformed reply) leaves the voice call stuck on "Thinking…" forever.
      // The buffered fragment is dropped, not spoken: the reply the user gets
      // is the error banner, not a half sentence.
      _p.sentenceBuffer = '';
      _p.sentenceBroadcast.add('__DONE__');

      // Restore original model if swapped for call mode
      if (t.originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: t.originalModelName,
        );
      }

      _d.notify();
    } finally {
      _llmProvider?.endMouthSpeech();
      // The per-turn realism speaker pin lives only while we generate. Clear it
      // on every exit (normal completion, early return, or error) so the next
      // turn's pre-pick window (e.g. _applyMoodDecay) keeps its prior
      // nextCharacter-based behaviour instead of seeing a stale speaker.
      _groupStore.turnSpeakerId = null;
      // Stopped, refused or failed before the reply landed: the picked
      // member never spoke, so Try again (or the next send) is theirs.
      final rotation = t.rotationBeforePick;
      if (rotation != null && !t.replyLanded) {
        _session.groupManager?.restoreRotation(rotation);
      }
      _awayPulse.finishTurn();
      // Settling over, on EVERY exit — restore the CALLER's hold (regen keeps
      // it raised across its swipe-merge); a latched flag would wedge input.
      _p.isPostGenerating = callerHeldSettling;
      if (!_p.isPostGenerating) {
        _p.postGenAbortRequested = false;
        _isCancellingRealismEval = false;
        _realismEvalCancelled = false;
        // Listeners (web isSettlingTurn → chat_updated) only see the clear
        // through a notification. The flag alone does not broadcast.
        _d.notify();
      }
    }
  }

  /// The request is in flight (the prompt assembler started the stream):
  /// the prefill phase, its prompt token count and the perf poll.
  void enterPrefill(GenTurn t, String prompt) {
    // ── Phase: Prefilling ──
    // The HTTP request is now in flight. For KoboldCPP, the model is
    // processing the prompt (prefill/eval). No tokens arrive until
    // prefill finishes. Poll /api/extra/perf for real-time status.
    _p.generationPhase = GenerationPhase.prefilling;
    _p.prefillStartTime = DateTime.now();
    _p.prefillPromptTokens = (prompt.length / 4).ceil(); // Rough placeholder
    _d.notify();

    // If using local KoboldCPP, poll /api/extra/perf during prefill
    // to get real prompt processing metrics.
    final isLocalBackend = t.isLocalBackend =
        _llmProvider == null || _llmProvider!.isLocal;
    if (isLocalBackend) {
      // Get REAL token count from the model's tokenizer (async, updates UI when done)
      _koboldService.countTokens(prompt).then((realCount) {
        if (_p.generationPhase == GenerationPhase.prefilling && realCount > 0) {
          _p.prefillPromptTokens = realCount;
          debugPrint(
            '[Prefill] Actual token count from tokenizer: $realCount (was ~${(prompt.length / 4).ceil()} est)',
          );
          _d.notify();
        }
      });

      t.perfPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_p.generationPhase != GenerationPhase.prefilling) {
          t.perfPoller?.cancel();
          t.perfPoller = null;
          return;
        }
        final perf = await _koboldService.fetchPerf();
        if (perf != null) {
          _p.lastPerfData = perf;
          _d.notify();
        }
      });
    }
  }
}
