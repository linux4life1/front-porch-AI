// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pre-gen judge builders: verifier, needs impact, RealismEvals,
// ObjectiveProposal. Engine, post-gen trio, and tools transport
// stay on wiring_evals. Injection is a different file.
// objectivesActive stays the live AND.

part of '../chat_service.dart';

extension ChatServiceWiringEvalJudges on ChatService {
  RealismVerification _buildRealismVerifier() {
    return RealismVerification(
      fireLLMEval: (p, {onChunk}) => _fireLLMEval(
        p,
        onChunk: onChunk,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'director',
      ),
      stripThinkBlocks: _stripThinkBlocks,
      extractJsonInt: _extractJsonInt,
      extractJsonBool: _extractJsonBool,
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getIsObserverMode: () => _observerMode,
      getUserName: () => _userPersonaService.persona.name,
      getMessages: () => _messages,
      getRealismVerificationEnabled: () =>
          (_activeCharacter?.frontPorchExtensions?.realismVerificationEnabled ??
              false) &&
          _realismEnabled &&
          (_activeGroup == null || !_observerMode),
      getVerificationMaxReprocesses: () =>
          _activeCharacter
              ?.frontPorchExtensions
              ?.realismVerificationMaxReprocesses ??
          1,
      getVerificationStrictness: () =>
          _activeCharacter
              ?.frontPorchExtensions
              ?.realismVerificationStrictness ??
          3,
      captureRealismState: _captureRealismState,
      getPreTurnNeedsVector: () => _needsSimulation.vector,
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      onVerificationPhase: (verifying, {pass = 0, max = 1}) {
        _isVerifyingRealism = verifying;
        _verificationPass = pass;
        _verificationMaxPasses = max;
        notifyListeners();
      },
      isCancelling: () => _isCancellingRealismEval,
    );
  }

  // ── Needs Impact Evaluator (post-buffer: straight model deltas + optional Director) ──
  // See CLAUDE.md (buffer removal complete; authority branch via cb; 1:1/group parity).
  NeedsImpactEvaluator _buildNeedsImpactEvaluator() {
    return NeedsImpactEvaluator(
      evaluateNeedsImpactCall: _llmEvalEngine.evaluateNeedsImpactCall,
      verifyRealismOutput: _realismVerifier.verify,
      fireLLMEval: (p, {onChunk}) => _fireLLMEval(
        p,
        onChunk: onChunk,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'needs',
      ),
      getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
      setPendingRealismMetadata: _writePendingRealismMetadata,
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getIsObserverMode: () => _observerMode,
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getGroupNeeds: _getGroupNeeds,
      setGroupNeeds: _setGroupNeeds,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getMessages: () => _messages,
      needsSimulation: _needsSimulation,
      getNeedsSimEnabled: () => _needsSimEnabled,
      getRealismEnabled: () => _realismEnabled,
      getNeedsModelAuthorityEnabled: () =>
          (_activeCharacter
              ?.frontPorchExtensions
              ?.realismNeedsDirectorAuthority ??
          false),
      getNeedsSimStrength: () =>
          (_activeCharacter?.frontPorchExtensions?.needsSimStrength ?? 1),
    );
  }

  RealismEvals _buildRealismEvals() {
    return RealismEvals(
      fireLLMEval: (p, {onChunk}) => _fireLLMEval(
        p,
        onChunk: onChunk,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'realism',
      ),
      fireTightEval: (prompt, {onChunk, wallClockTimeout}) async {
        var aborted = false;
        final raw = await _fireLLMEval(
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
                _stripThinkBlocks(acc),
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
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      isEvalCancelled: () =>
          _isCancellingRealismEval ||
          _realismEvalCancelled ||
          _isStaleGreetingEval(),
      stripThinkBlocks: _stripThinkBlocks,
      extractJsonInt: _extractJsonInt,
      extractJsonBool: _extractJsonBool,
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getIsObserverMode: () => _observerMode,
      getUserName: () => _userPersonaService.persona.name,
      getRealismEnabled: () => _realismEnabled,
      getObjectivesEnabled: () => objectivesActive,
      getMessages: () => _messages,
      getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
      setPendingRealismMetadata: _writePendingRealismMetadata,
      captureRealismState: _captureRealismState,
      getCharacterEmotion: () => _characterEmotion,
      setCharacterEmotion: (v) => _characterEmotion = v,
      getEmotionIntensity: () => _emotionIntensity,
      setEmotionIntensity: (v) => _emotionIntensity = v,
      relationshipService: _relationshipService,
      nsfwService: _nsfwService,
      timeService: _timeService,
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
        growth: _growthService.growthLinesFor(card),
      ),
      getPrimaryObjective: () => primaryObjective,
      getActiveObjectives: () => _activeObjectives,
      // The EVALUATED speaker's ambitions. Realism evals run under speaker
      // impersonation (_activeCharacter is temporarily whoever is being
      // scored), so this reads the right character in a group without a
      // second code path — and it goes through the same public ambitionsFor
      // merge the sidebar and the web read, so the model and the user can
      // never be shown different progress.
      //
      // Gated on the SAME condition as the per-turn ambition injection
      // (ambitionsEnabled && objectivesActive), and for the same reason: with
      // either switch off, nothing can ever move ambition progress, so paying
      // per turn to steer quests toward a frozen goal bills the user for a
      // mechanism they turned off. Empty here removes the roster, the steering
      // paragraph and the serves_ambition field from the prompt entirely.
      getAmbitions: () =>
          _activeCharacter == null ||
              !_storageService.realismSettings.ambitionsEnabled ||
              !objectivesActive
          ? const []
          : ambitionsFor(_activeCharacter!),
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
      // `_activeCharacter` the ambition roster above does — during the realism
      // dance that is the speaker being evaluated, and the two must not
      // disagree about whose card they describe.
      getPreferences: () {
        final ext = _activeCharacter?.frontPorchExtensions;
        if (ext == null) return '';
        final adult = _storageService.realismSettings.adultThemesEnabled;
        return RealismPromptBuilder.preferencesBlock(
          charName: _activeCharacter!.name,
          likes: ext.likes,
          dislikes: ext.dislikes,
          intimateInto: adult ? ext.intimateInto : const [],
          intimateNotInto: adult ? ext.intimateNotInto : const [],
          // Same resolution as the injection's gate (wiring_injection): the
          // switch AND the engine. The engine is implied here — an eval only
          // runs with realism on — but it is stated so the two call sites read
          // identically and cannot drift.
          intimateAgency:
              _storageService.realismSettings.intimateAgencyEnabled &&
              _realismEnabled,
        );
      },
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      setObjective:
          (
            text, {
            isPrimary = false,
            autoGenerateTasks = false,
            servedAmbition,
          }) => setObjective(
            text,
            isPrimary: isPrimary,
            autoGenerateTasks: autoGenerateTasks,
            servedAmbition: servedAmbition,
            // Eval-proposed objectives belong to the turn being generated —
            // record them so regen can roll them back (turn-ops; the UI's
            // direct setObjective calls stay unrecorded).
            recordTurnOps: true,
          ),
      verifyRealismOutput: _realismVerifier.verify,
    );
  }

  ObjectiveProposal _buildObjectiveProposal() {
    return ObjectiveProposal(
      stripThinkBlocks: _stripThinkBlocks,
      getLlmService: () => _sideLaneLlm,
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getIsObserverMode: () => _observerMode,
      getUserName: () => _userPersonaService.persona.name,
      getRealismEnabled: () => _realismEnabled,
      getMessages: () => _messages,
      getActiveObjectives: () => _activeObjectives,
      tasksForObjective: tasksForObjective,
      loadActiveObjectives: _loadActiveObjectives,
      saveObjectiveTasks: (id, json) async {
        await _db.updateObjective(
          ObjectivesCompanion(id: drift.Value(id), tasks: drift.Value(json)),
        );
      },
      deactivateObjective: (id) async {
        // Only the completion check retires through this cb (the UI's
        // clearObjective has its own db call) — record the turn-op so regen
        // can reactivate a quest the invalidated turn retired. Armed-gated:
        // manual "Check now" retirements are user actions, not turn ops.
        if (_objectiveTurnOpsArmed) {
          _recordObjectiveTurnOp({'op': 'deactivated', 'id': id});
        }
        await _db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(id),
            active: const drift.Value(false),
          ),
        );
      },
      markTaskCompleted: markTaskCompleted,
      getIsCheckingCompletion: () => _isCheckingCompletion,
      setIsCheckingCompletion: (v) => _isCheckingCompletion = v,
      onNotify: notifyListeners,
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      // The completion check runs pre-generation; the flags are consumed by
      // _maybeRunJournalPass/_maybeRunGrowthPass post-generation (a finished
      // quest is a story beat worth journaling AND a moment characters grow).
      onObjectiveCompleted: () => _requestSalienceKick(),
      // Ambitions (Living Time §6): a whole quest finishing is the ONE moment
      // ambition progress can move. Fire-and-forget; owner resolved from the
      // objective row's characterId (per-character in groups by construction).
      onQuestAchieved: (obj) {
        if (_isHeldTodayObjective(obj)) {
          unawaited(_onTodayObjectiveCompleted(obj));
          return;
        }
        // The Ambitions switch has to stop the WORK, not just the display.
        // Without this, turning ambitions off still spent a model call on
        // every quest completion — a switch that hid the feature while
        // continuing to bill for it.
        if (!_storageService.realismSettings.ambitionsEnabled) return;
        final sessionId = _currentSessionId;
        if (sessionId == null) return;
        final card =
            _groupCharacters
                .where((c) => _getCharacterIdFromCard(c) == obj.characterId)
                .firstOrNull ??
            (_activeCharacter != null &&
                    _getCharacterIdFromCard(_activeCharacter!) ==
                        obj.characterId
                ? _activeCharacter
                : null);
        final ambitions = card?.frontPorchExtensions?.ambitions ?? const [];
        if (card == null || ambitions.isEmpty) return;
        unawaited(
          _ambitionService.onQuestAchieved(
            sessionId: sessionId,
            characterId: obj.characterId,
            characterName: card.name,
            objectiveText: obj.objective,
            ambitions: ambitions,
            // v46: if the proposal already said which mountain this quest
            // climbs, the judge does not have to guess it again — it only has
            // to rule on how big a step it was. Null for user-typed quests and
            // for everything created before the column existed, which fall
            // back to the original "which, if any?" question.
            servedAmbition: obj.servedAmbition,
            storyDay: _timeService.dayCount,
            storyClock: _timeService.storyClockIso,
          ),
        );
      },
    );
  }
}
