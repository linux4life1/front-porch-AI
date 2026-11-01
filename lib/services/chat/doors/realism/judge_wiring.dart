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
//
// Pre-gen judge builders: RealismEvals and ObjectiveProposal. The engine,
// the post-gen trio, the verifier and the dispatch are eval_wiring.dart;
// the tools transport is eval_transport.dart. objectivesActive stays the
// live AND.

import 'dart:async';

import 'package:drift/drift.dart' as drift;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/storage_service.dart';

extension RealismJudgeWiring on RealismGraph {
  RealismEvals buildEvals() {
    return RealismEvals(
      fireLLMEval: (p, {onChunk}) => transport.fireLLMEval(
        p,
        onChunk: onChunk,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'realism',
      ),
      fireTightEval: (prompt, {onChunk, wallClockTimeout}) async {
        var aborted = false;
        final raw = await transport.fireLLMEval(
          prompt,
          onChunk: onChunk,
          repeatPenalty: kScalarEvalRepeatPenalty,
          label: 'realism-fused',
          salvageReasoning: false,
          maxLength: kEvalRecoveryMaxLength,
          wallClockTimeout: wallClockTimeout,
          abortClientOnStop: true,
          onGuardAbort: () => aborted = true,
          stopWhen: (acc) =>
              usableEvalJsonText(
                stripEvalThinkBlocks(acc),
                tools: kOneShotEvalTools,
                toolChoice: kOneShotTool,
                callToText: (resp) =>
                    realismToolCallToJson(kOneShotTool, resp.calls),
              ) !=
              null,
        );
        return fusedTextFromRaw(raw, aborted: aborted);
      },
      // Tools transport (realism_tools.dart): same door + probe memory the
      // Journal and Growth passes use, so a backend answers the "can you speak
      // tools?" question at most once per run across all three systems.
      fireToolEval: transport.fireToolEval,
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      isEvalCancelled: () =>
          evalStatus.cancelling ||
          evalStatus.cancelled ||
          _doors.turn().greetingEval.isStale(),
      stripThinkBlocks: stripEvalThinkBlocks,
      extractJsonInt: evalJsonInt,
      extractJsonBool: evalJsonBool,
      getActiveCharacter: () => session.activeCharacter,
      getActiveGroup: () => session.activeGroup,
      getIsObserverMode: () => _doors.entry().director.observerMode,
      getUserName: () => deps.services.personas.persona.name,
      getRealismEnabled: () => controls.realismEnabled,
      // A Feelings re-score leaves the turn's quests as they were.
      getObjectivesEnabled: () =>
          controls.objectivesActive &&
          !_doors.edits().reprocess.rescoringFeelings,
      getMessages: () => session.messages,
      getPendingRealismMetadata: () => registers.pending ?? {},
      setPendingRealismMetadata: growthDesk.writePendingRealismMetadata,
      captureRealismState: snapshot.capture,
      getCharacterEmotion: () => registers.emotion,
      setCharacterEmotion: (v) => registers.emotion = v,
      getEmotionIntensity: () => registers.intensity,
      setEmotionIntensity: (v) => registers.intensity = v,
      getEmotionCause: () => registers.cause,
      setEmotionCause: (v) => registers.cause = v,
      getEmotionHeldTurns: () => registers.heldTurns,
      setEmotionHeldTurns: (v) => registers.heldTurns = v,
      relationshipService: relationship,
      nsfwService: nsfw,
      timeService: time,
      getExpressionEnabled: () =>
          _storageService.expressionSettings.expressionEnabled,
      // Judge dossier: same identity the generation sees (personality +
      // description + growth-ring lines when enabled), budget-capped in the
      // builder. Under group impersonation `card` is the current speaker, so
      // per-speaker parity holds without extra dispatch here.
      getCharacterDossier: (card) => RealismPromptBuilder.characterDossier(
        name: card.name,
        personality: card.personality,
        description: card.description,
        growth: growthService.growthLinesFor(card),
      ),
      getPrimaryObjective: () => _doors.objectives().primaryObjective,
      getActiveObjectives: () => _doors.objectives().activeObjectives,
      // The EVALUATED speaker's ambitions. Realism evals run under speaker
      // impersonation (session.activeCharacter is temporarily whoever is being
      // scored), so this reads the right character in a group without a
      // second code path — and it goes through the same ambitionsFor merge
      // the sidebar and the web read, so the model and the user can never be
      // shown different progress.
      //
      // Gated on the SAME condition as the per-turn ambition injection
      // (ambitionsEnabled && objectivesActive), and for the same reason: with
      // either switch off, nothing can ever move ambition progress, so paying
      // per turn to steer quests toward a frozen goal bills the user for a
      // mechanism they turned off. Empty here removes the roster, the steering
      // paragraph and the serves_ambition field from the prompt entirely.
      getAmbitions: () =>
          session.activeCharacter == null ||
              !_storageService.realismSettings.ambitionsEnabled ||
              !controls.objectivesActive
          ? const []
          : ambitionsFor(session.activeCharacter!),
      // PR 5: one shared source for the mutual opening — the ladder and the
      // refractory note read the identical stamp-backed truth.
      getMutualOpening: mutualAfterglowOpening,
      getPcdActive: pcdActive,
      // Likes & Dislikes — the SCORING half. Called once per prompt BUILD, not
      // once per turn (review, 2026-08-07 — the earlier comment here claimed
      // otherwise). What makes one-shot parity hold is that it is PURE: it
      // reads only the speaker's card and one setting, so relationship,
      // emotional and one-shot receive a byte-identical block. Keep it pure —
      // anything time-, counter- or random-dependent added here would break
      // both cross-path parity AND regen determinism at temperature 0.1.
      //
      // This is also the ONE place the 18+ switch is consulted for scoring:
      // with adult themes off the intimate pair is not passed, so it cannot
      // reach a prompt no matter which path runs. Reads the same
      // `session.activeCharacter` the ambition roster above does — during the
      // realism dance that is the speaker being evaluated, and the two must
      // not disagree about whose card they describe.
      getPreferences: () {
        final ext = session.activeCharacter?.frontPorchExtensions;
        if (ext == null) return '';
        final adult = _storageService.realismSettings.adultThemesEnabled;
        return RealismPromptBuilder.preferencesBlock(
          charName: session.activeCharacter!.name,
          likes: ext.likes,
          dislikes: ext.dislikes,
          intimateInto: adult ? ext.intimateInto : const [],
          intimateNotInto: adult ? ext.intimateNotInto : const [],
          // Same resolution as the injection's gate (injection_wiring): the
          // switch AND the engine. The engine is implied here — an eval only
          // runs with realism on — but it is stated so the two call sites read
          // identically and cannot drift.
          intimateAgency:
              _storageService.realismSettings.intimateAgencyEnabled &&
              controls.realismEnabled,
        );
      },
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      // The proposal gate (objectives-that-keep-up.md part 3). During the
      // realism dance `session.activeCharacter` is the speaker being
      // evaluated.
      getRecentEndedObjectives: _doors.objectives().recentEndedLines,
      getObjectiveIgnoreTokens: _doors.objectives().objectiveIgnoreTokens,
      isSideQuestCooldownActive: () {
        final card = session.activeCharacter;
        return card != null &&
            sideQuestCooldownActive(
              session.messages,
              session.characterIdFor(card),
            );
      },
      getSideQuestCap: () => deps.services.maxSecondaryObjectives,
      setObjective:
          (
            text, {
            isPrimary = false,
            autoGenerateTasks = false,
            servedAmbition,
          }) => _doors.objectives().writer.setObjective(
            text,
            isPrimary: isPrimary,
            autoGenerateTasks: autoGenerateTasks,
            servedAmbition: servedAmbition,
            // The judge proposed it: the character's own want.
            origin: kObjectiveOriginCharacter,
            // Eval-proposed objectives belong to the turn being generated —
            // record them so regen can roll them back (turn-ops; the UI's
            // direct setObjective calls stay unrecorded).
            recordTurnOps: true,
          ),
      verifyRealismOutput: verifier.verify,
    );
  }

  ObjectiveProposal buildObjectiveProposal() {
    final objectives = _doors.objectives();
    return ObjectiveProposal(
      stripThinkBlocks: stripEvalThinkBlocks,
      getLlmService: () => lanes.sideLane,
      getActiveCharacter: () => session.activeCharacter,
      ownerCard: objectives.ownerCard,
      getActiveGroup: () => session.activeGroup,
      getIsObserverMode: () => _doors.entry().director.observerMode,
      getUserName: () => deps.services.personas.persona.name,
      getRealismEnabled: () => controls.realismEnabled,
      getMessages: () => session.messages,
      getActiveObjectives: () => objectives.activeObjectives,
      tasksForObjective: objectives.tasks.tasksFor,
      loadActiveObjectives: objectives.loadActiveObjectives,
      saveObjectiveTasks: (id, json) async {
        await deps.services.db().updateObjective(
          ObjectivesCompanion(id: drift.Value(id), tasks: drift.Value(json)),
        );
      },
      // The goal sync's writes; each records its turn op only while the
      // turn-path check is armed, so a manual "Check now" stays the user's.
      writeSyncedTasks: objectives.completion.writeSyncedTasks,
      retireObjective: objectives.completion.retireFromSync,
      setObjectiveDormant: objectives.completion.setDormant,
      isHeldToday: planner.isHeldTodayObjective,
      getIsCheckingCompletion: () => objectives.isCheckingCompletion,
      // Every flip notifies: the web relay pushes the phone's goal-check
      // overlay (and its Skip) from it. The pre-reply check had no notify.
      setIsCheckingCompletion: (v) {
        objectives.isCheckingCompletion = v;
        deps.notify();
      },
      onNotify: deps.notify,
      fireToolEval: transport.fireToolEval,
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      // The completion check runs pre-generation; the flags are consumed by
      // the Journal pass and GrowthDesk.maybeRunGrowthPass post-generation (a
      // finished quest is a story beat worth journaling AND a moment
      // characters grow).
      onObjectiveCompleted: () => growthDesk.requestSalienceKick(),
      // Ambitions (Living Time §6): a whole quest finishing is the ONE moment
      // ambition progress can move. Fire-and-forget; owner resolved from the
      // objective row's characterId (per-character in groups by construction).
      onQuestAchieved: (obj) {
        if (planner.isHeldTodayObjective(obj)) {
          unawaited(planner.onTodayObjectiveCompleted(obj));
          return;
        }
        // The Ambitions switch has to stop the WORK, not just the display.
        // Without this, turning ambitions off still spent a model call on
        // every quest completion — a switch that hid the feature while
        // continuing to bill for it.
        if (!_storageService.realismSettings.ambitionsEnabled) return;
        final sessionId = session.currentSessionId;
        if (sessionId == null) return;
        final card =
            session.groupCharacters
                .where((c) => session.characterIdFor(c) == obj.characterId)
                .firstOrNull ??
            (session.activeCharacter != null &&
                    session.characterIdFor(session.activeCharacter!) ==
                        obj.characterId
                ? session.activeCharacter
                : null);
        final ambitionList = card?.frontPorchExtensions?.ambitions ?? const [];
        if (card == null || ambitionList.isEmpty) return;
        unawaited(
          ambitions.onQuestAchieved(
            sessionId: sessionId,
            characterId: obj.characterId,
            characterName: card.name,
            objectiveText: obj.objective,
            ambitions: ambitionList,
            // v46: if the proposal already said which mountain this quest
            // climbs, the judge does not have to guess it again — it only has
            // to rule on how big a step it was. Null for user-typed quests and
            // for everything created before the column existed, which fall
            // back to the original "which, if any?" question.
            servedAmbition: obj.servedAmbition,
            storyDay: time.dayCount,
            storyClock: time.storyClockIso,
          ),
        );
      },
      onObjectiveStale: (obj) {
        if (!planner.isHeldTodayObjective(obj)) return;
        final today = _doors.sessions().today;
        final held = today.todaySentence ?? obj.objective;
        planner.recordTodayPointerOp();
        today.todayObjectiveId = null;
        today.todayObjectiveText = null;
        today.setTodaySentence(null);
        unawaited(() async {
          await planner.journalResolvedToday(
            held,
            fate: PlannerTodayFate.abandoned,
          );
          await planner.persistTodayObjectiveId(null);
        }());
      },
    );
  }
}

extension on RealismGraph {
  StorageService get _storageService => deps.services.storage;
  RealismDoors get _doors => deps.doors;
}
