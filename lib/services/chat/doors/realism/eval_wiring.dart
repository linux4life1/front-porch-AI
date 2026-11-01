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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/kobold_service.dart';

/// The shared eval engine, the post-gen trio (pockets / climax /
/// reply-facts) and the leaves that run on them, the verifier, the Needs
/// impact judge, the pre-gen dispatch (judges and the dance) and Reprocess
/// Needs. The RealismEvals and objective proposal builders are
/// judge_wiring.dart.
extension RealismEvalWiring on RealismGraph {
  // ── LLM eval engine: the central eval firing (streaming/retry/cancel,
  // 4000/0.1/no-reasoning), the think strip, the JSON extractors and the
  // Needs impact call. Wired with granular callbacks for 1:1 vs group (the
  // dance impersonates the speaker), the pending/emotion registers and the
  // capture. The callers own the post-eval save and notify.
  LlmEvalEngine buildLlmEvalEngine() {
    return LlmEvalEngine(
      getActiveCharacter: () => session.activeCharacter,
      getActiveGroup: () => session.activeGroup,
      getIsObserverMode: () => _doors.entry().director.observerMode,
      getUserName: () => deps.services.personas.persona.name,
      getRealismEnabled: () => controls.realismEnabled,
      getMessages: () => session.messages,
      // Shared tools transport for the needs-impact eval (one probe per
      // backend identity, app-wide).
      fireToolEval: transport.fireToolEval,
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
      getPreferTextEvals: () =>
          deps.services.storage.realismSettings.preferTextEvals,
      getLlmService: () => lanes.sideLane,
      getIsLocal: () => lanes.sideLaneIsKobold,
      getKoboldService: () {
        final s = lanes.sideLane;
        return s is KoboldService ? s : null;
      },
      reconnectIfAlive: () async {
        final s = lanes.sideLane;
        if (s is KoboldService) await s.reconnectIfAlive();
      },
      ensureServerIdle: () async {
        final s = lanes.sideLane;
        if (s is KoboldService) await s.ensureServerIdle();
      },
      getIsCancellingRealismEval: () => evalStatus.cancelling,
      getRealismEvalCancelled: () =>
          evalStatus.cancelled || _doors.turn().greetingEval.isStale(),
      getPendingRealismMetadata: () => registers.pending ?? {},
      setPendingRealismMetadata: growthDesk.writePendingRealismMetadata,
      captureRealismState: snapshot.capture,
      getCharacterEmotion: () => registers.emotion,
      setCharacterEmotion: (v) => registers.emotion = v,
      getEmotionIntensity: () => registers.intensity,
      setEmotionIntensity: (v) => registers.intensity = v,
      relationshipService: relationship,
    );
  }

  /// Which cast member said [msg]. See [resolveGroupSpeakerForMessage].
  CharacterCard? speakerFor(ChatMessage msg) =>
      resolveGroupSpeakerForMessage(session.groupCharacters, msg);

  // ── Pockets, Afterglow and their fused reply-facts transport ──
  // Pockets is its OWN pass, deliberately: the settled ruling is that it
  // rides no other feature's eval. It shares only the transport — the same
  // probe-and-fallback every other structured eval uses, so a tool-less
  // backend gets the flat-JSON floor for free.
  PocketsLedger buildPocketsLedger() => PocketsLedger(
    scope,
    hostRecord: () => hostPockets,
    setHostRecord: (p) => hostPockets = p,
    originLibraryCardFor: (member) =>
        _doors.entry().roster.originLibraryCardFor(member),
    currentSessionId: () => session.currentSessionId,
    storyDayCount: () => time.morningAnchoredDayCount,
    memorySettings: () => deps.services.storage.memorySettings,
    itemCards: () => itemCards,
  );

  PocketsRewinds buildPocketsRewinds() => PocketsRewinds(
    session.messages,
    pocketsLedger,
    itemCards: () => itemCards,
  );

  PocketsPass buildPocketsPass() => PocketsPass(
    scope,
    pocketsLedger,
    PocketsEval(
      fire: transport.structured(PocketsEval.kPocketsTool, 'pockets'),
    ),
    fusedReply: () => replyFacts.raw,
    itemCards: () => itemCards,
    currentSessionId: () => session.currentSessionId,
    storyDayCount: () => time.morningAnchoredDayCount,
    memorySettings: () => deps.services.storage.memorySettings,
  );

  // The fused reply-facts call: one round trip for climax + pockets +
  // posture when two or more of them are live; the composition rules that
  // keep every feature on its own gate are documented on the leaf. Built per
  // turn by ReplyFacts.prefetch: the leaf is a stateless wrapper over this
  // fire. Not a hot path (once per reply, never per frame).
  ReplyFacts buildReplyFacts() => ReplyFacts(
    scope,
    pocketsLedger,
    afterglowActive: () => afterglow.active,
    storyDayCount: () => time.morningAnchoredDayCount,
    buildEval: () => ReplyFactsEval(
      fire: transport.structured(ReplyFactsEval.kReplyFactsTool, 'reply_facts'),
    ),
  );

  // Afterglow's climax check is its own pass (see ClimaxEval) and shares
  // only the transport, never another feature's call.
  AfterglowPass buildAfterglow() => AfterglowPass(
    scope,
    ClimaxEval(fire: transport.structured(ClimaxEval.kClimaxTool, 'climax')),
    fusedReply: () => replyFacts.raw,
    isGuestAuthoredMessage: (m) =>
        _doors.cast().guests.isGuestAuthoredMessage(m),
    resolveGroupSpeakerForMessage: speakerFor,
  );

  /// The char→char judge (its own tool and pass; see CastFeelingsJudge).
  CastFeelingsJudge buildCastFeelingsJudge() => CastFeelingsJudge(
    fire: transport.structured(kCastFeelingsToolName, 'cast_feelings'),
  );

  RealismVerification buildVerifier() {
    return RealismVerification(
      fireLLMEval: (p, {onChunk}) => transport.fireLLMEval(
        p,
        onChunk: onChunk,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'director',
      ),
      stripThinkBlocks: stripEvalThinkBlocks,
      extractJsonInt: evalJsonInt,
      extractJsonBool: evalJsonBool,
      getActiveCharacter: () => session.activeCharacter,
      getActiveGroup: () => session.activeGroup,
      getIsObserverMode: () => _doors.entry().director.observerMode,
      getUserName: () => deps.services.personas.persona.name,
      getMessages: () => session.messages,
      getRealismVerificationEnabled: () =>
          (session
                  .activeCharacter
                  ?.frontPorchExtensions
                  ?.realismVerificationEnabled ??
              false) &&
          controls.realismEnabled &&
          (session.activeGroup == null ||
              !_doors.entry().director.observerMode),
      getVerificationMaxReprocesses: () =>
          session
              .activeCharacter
              ?.frontPorchExtensions
              ?.realismVerificationMaxReprocesses ??
          1,
      getVerificationStrictness: () =>
          session
              .activeCharacter
              ?.frontPorchExtensions
              ?.realismVerificationStrictness ??
          3,
      captureRealismState: snapshot.capture,
      getPreTurnNeedsVector: () => needs.vector,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      onVerificationPhase: (verifying, {pass = 0, max = 1}) {
        evalStatus
          ..verifying = verifying
          ..verificationPass = pass
          ..verificationMaxPasses = max;
        deps.notify();
      },
      isCancelling: () => evalStatus.cancelling,
    );
  }

  // ── Needs Impact Evaluator (straight model deltas + optional Director) ──
  // The authority branch rides a callback; 1:1 and group share it.
  NeedsImpactEvaluator buildNeedsImpact() {
    return NeedsImpactEvaluator(
      evaluateNeedsImpactCall: llmEvalEngine.evaluateNeedsImpactCall,
      verifyRealismOutput: verifier.verify,
      fireLLMEval: (p, {onChunk}) => transport.fireLLMEval(
        p,
        onChunk: onChunk,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'needs',
      ),
      getPendingRealismMetadata: () => registers.pending ?? {},
      setPendingRealismMetadata: growthDesk.writePendingRealismMetadata,
      getActiveCharacter: () => session.activeCharacter,
      getActiveGroup: () => session.activeGroup,
      getIsObserverMode: () => _doors.entry().director.observerMode,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getGroupNeeds: groups.needsOf,
      setGroupNeeds: groups.setNeeds,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: _h.characterIdFor,
      getMessages: () => session.messages,
      needsSimulation: needs,
      getNeedsSimEnabled: () => needsPass.active,
      getRealismEnabled: () => controls.realismEnabled,
      getNeedsModelAuthorityEnabled: () =>
          (session
              .activeCharacter
              ?.frontPorchExtensions
              ?.realismNeedsDirectorAuthority ??
          false),
    );
  }

  RealismJudges buildJudges() => RealismJudges(
    scope,
    realismEvals: () => evals,
    verifier: () => verifier,
    fireLLMEval: transport.fireLLMEval,
    fireToolEval: transport.fireToolEval,
    toolProbe: transport.probe,
    backendIdentity: () => transport.backendIdentity,
    writePending: growthDesk.writePendingRealismMetadata,
    evalCancelled: () => evalStatus.cancelled,
    oneShotActive: () => controls.oneShotActive,
    personaName: () => deps.services.personas.persona.name,
    dispatchStagger: deps.services.evalStagger,
    directing: () => _doors.entry().director.directing,
  );

  RealismDance buildDance() => RealismDance(
    scope,
    needsPass: () => needsPass,
    judges: () => judges,
    snapshot: () => snapshot,
    realismActiveThisMode: () => realismActiveThisMode,
    speakerIsSoft: (speaker) => _doors.cast().roster.speakerIsSoft(speaker),
    withWorkerLane: (work) => lanes.withWorkerLane(work),
    tickRefractoryPerReply: afterglow.tickPerReply,
    stampGroupUserTurnBaseline: _h.stampGroupUserTurnBaseline,
    applyMoodDecay: restores.applyMoodDecay,
    seedOpeningPosture: () => _doors.cast().baseline.seedOpeningPosture(),
    objectives: () => _doors.objectives().activeObjectives,
    setObjectives: (v) => _doors.objectives().activeObjectives = v,
    objectivesFor: (card) => _doors.objectives().getActiveObjectivesFor(card),
    evalCancelled: () => evalStatus.cancelled,
    setEvaluating: (v) => evalStatus.evaluating = v,
    streamText: () => evalStatus.streamText,
    setStreamText: (v) => evalStatus.streamText = v,
    chunkTimer: () => evalStatus.chunkTimer,
    setChunkTimer: (t) => evalStatus.chunkTimer = t,
  );

  /// The skip step for a user line or a /narrate beat. Stateless, so it
  /// is built per use.
  PlayerSkip playerSkip() => PlayerSkip(
    time: time,
    reader: SkipReader(
      fireLLMEval: (p) => transport.fireLLMEval(p, label: 'skip'),
      stripThinkBlocks: llmEvalEngine.stripThinkBlocks,
      fireToolEval: transport.fireToolEval,
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
    ),
  );

  NeedsReprocess buildNeedsReprocess() => NeedsReprocess(
    scope,
    needsActive: () => needsPass.active,
    isTurnBusy: () => _doors.turn().isTurnBusy,
    speakerForMessage: speakerFor,
    targetFor: (index) =>
        _doors.edits().reprocess.targets.reprocessNeedsTargetFor(index),
    loadIntoScalars: (id) => dance.loadIntoScalars(id),
    saveScalarsIntoGroup: (id) => dance.saveScalarsIntoGroup(id),
    evaluator: () => needsImpact,
    setVerifying: (on, {pass, maxPasses}) {
      evalStatus.verifying = on;
      if (pass != null) evalStatus.verificationPass = pass;
      if (maxPasses != null) evalStatus.verificationMaxPasses = maxPasses;
    },
    clearEvalCancelled: () => evalStatus.cancelled = false,
    waitForEvalIdle: () async {
      final koboldForReprocess = deps.services.llmProvider()?.koboldService;
      if (koboldForReprocess != null) {
        await koboldForReprocess.waitForIdle();
      }
    },
  );
}

extension on RealismGraph {
  RealismShellHooks get _h => deps.hooks;
  RealismDoors get _doors => deps.doors;
}
