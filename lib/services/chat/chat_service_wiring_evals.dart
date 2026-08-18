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

/// Builders for the Realism/Needs eval pipeline (the LLM eval engine, the
/// realism verifier, the needs-impact evaluator, the 5 realism evals, and
/// objective proposal handling) plus the shared tools-transport surface
/// (`_fireToolEval` / `_evalBackendIdentity` / the tool-support tester
/// builder). Extracted verbatim from `chat_service.dart` — zero behaviour
/// change; every callback closure is byte-identical to its old inline form.
extension ChatServiceWiringEvals on ChatService {
  // ── LLM Eval Engine (step 9: _fireLLMEval + strip + extract + needs impact cb) ──
  // Plain class (not ChangeNotifier). Owns the central eval firing (streaming/retry/cancel, 4000/0.1/no-reasoning),
  // central strip (completed+unclosed), JSON extractors, evaluateNeedsImpactCall (for needs_impact_evaluator).
  // The 5 realism eval prompt builders + calls (rel/emotion/phys/narr w/ proposed_objective, oneShot) moved to
  // sibling leaf realism_evals.dart (step 10); this engine provides fire/strip/extract cbs to it (granular).
  // objective proposal handling + generateObjectiveTasks + _checkTaskCompletionInBackground moved to
  // sibling leaf objective_proposal.dart (step 11); this engine provides strip cb to it (for 2000 paths).
  // Wired with granular cbs for 1:1 vs group (via impersonation for speaker), test overrides,
  // pending/emotion state, capture, + service deps (rel) .
  // (onNotify/onSaveChat removed in step 10 fix round 1 + step11: oneShot populates pending snapshot;
  // god owns the post-eval _saveChat/notify in pre-turn + baseline paths to avoid double + races;
  // on* dead post step11 objective move, cleaned).
  // 0 @Deprecated shims. 0 new god private _ methods beyond the required thin delegates (_fireLLMEval, _stripThinkBlocks, _extractJson*, evaluateNeedsImpactCall; the 5 _evaluate*Call thins now point to realism_evals; generate/check thins now to objective_proposal; the void _ count grep stayed 15; +1 late final only; thins/calls/late final only per plan). (cross-ref setActiveCharacter:1572 etc)
  // Stateless/prompt-only: no reset calls needed. Reset hygiene comments list full set + llm_eval_engine (stateless or prompt-only;
  // no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed) + cross-refs (e.g. setActiveCharacter:1572). Both startNew branches explicit.
  // 1:1 vs group + oneShot vs normal dispatch/parity preserved exactly (cbs + impersonation temp re-load; qualified).
  // aug exercising only passive/qualified (no llm-eval-specific aug file edits; resets/loads/greetings/post hit by pre-existing
  // startNew/setActive/_loadLast/group in key suites; full eval/JSON/strip + needs impact only in dedicated + manual;
  // objective proposal/gen/check exercised via god thins generate/check ; qualified notes only in dedicated header + god + MD per precedent).
  LlmEvalEngine _buildLlmEvalEngine() {
    return LlmEvalEngine(
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getIsObserverMode: () => _observerMode,
      getUserName: () => _userPersonaService.persona.name,
      getRealismEnabled: () => _realismEnabled,
      getMessages: () => _messages,
      // Shared tools transport for the needs-impact eval (one probe per
      // backend identity, app-wide).
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      getLlmService: () =>
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService,
      getIsLocal: () => testLlmServiceOverride != null
          ? testIsLocalOverride
          : (_llmProvider?.isLocal ?? false),
      getKoboldService: () => _llmProvider?.koboldService,
      reconnectIfAlive: () async {
        final k = _llmProvider?.koboldService;
        if (k != null) await k.reconnectIfAlive();
      },
      ensureServerIdle: () async {
        final k = _llmProvider?.koboldService;
        if (k != null) await k.ensureServerIdle();
      },
      getIsCancellingRealismEval: () => _isCancellingRealismEval,
      getRealismEvalCancelled: () => _realismEvalCancelled,
      getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
      setPendingRealismMetadata: (v) => _pendingRealismMetadata = v,
      captureRealismState: _captureRealismState,
      getCharacterEmotion: () => _characterEmotion,
      setCharacterEmotion: (v) => _characterEmotion = v,
      getEmotionIntensity: () => _emotionIntensity,
      setEmotionIntensity: (v) => _emotionIntensity = v,
      relationshipService: _relationshipService,
    );
  }

  // ── Pockets & Wardrobe (docs/design/pockets-and-preferences.md Part 1) ──
  // Its OWN pass, deliberately: the settled ruling is that Pockets rides no
  // other feature's eval. It shares only the transport — the same
  // probe-and-fallback every other structured eval uses, so a tool-less
  // backend gets the flat-JSON floor for free.
  PocketsEval _buildPocketsEval() {
    return PocketsEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            return fireStructuredEval(
              probe: _toolProbe,
              backendIdentity: _evalBackendIdentity,
              debugLabel: debugLabel,
              tools: tools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(PocketsEval.kPocketsTool, resp.calls),
              fireToolEval: _fireToolEval,
              fireTextEval: (p, {onChunk}) => _fireLLMEval(
                p,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'pockets',
              ),
            );
          },
    );
  }

  // ── The fused reply-facts call (ReplyFactsEval) ──
  // One round trip for climax + pockets + posture when two or more of them
  // are live; the composition rules that keep every feature on its own gate
  // are documented on the leaf. Same transport wiring as its three siblings —
  // but constructed PER TURN by _prefetchReplyFacts rather than held as a
  // late final: the leaf is a stateless wrapper over this fire closure, and
  // one small allocation per turn is what kept the shell under the god-file
  // ratchet. Not a hot path (once per reply, never per frame).
  ReplyFactsEval _buildReplyFactsEval() {
    return ReplyFactsEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            return fireStructuredEval(
              probe: _toolProbe,
              backendIdentity: _evalBackendIdentity,
              debugLabel: debugLabel,
              tools: tools,
              buildPrompt: buildPrompt,
              callToText: (resp) => realismToolCallToJson(
                ReplyFactsEval.kReplyFactsTool,
                resp.calls,
              ),
              fireToolEval: _fireToolEval,
              fireTextEval: (p, {onChunk}) => _fireLLMEval(
                p,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'reply_facts',
              ),
            );
          },
    );
  }

  // ── Afterglow's climax check (its own pass; see ClimaxEval) ──
  // Shares only the transport, never another feature's call — the same
  // probe-and-fallback every structured eval uses, so a tool-less backend gets
  // the flat-JSON floor for free.
  ClimaxEval _buildClimaxEval() {
    return ClimaxEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            return fireStructuredEval(
              probe: _toolProbe,
              backendIdentity: _evalBackendIdentity,
              debugLabel: debugLabel,
              tools: tools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(ClimaxEval.kClimaxTool, resp.calls),
              fireToolEval: _fireToolEval,
              fireTextEval: (p, {onChunk}) => _fireLLMEval(
                p,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'climax',
              ),
            );
          },
    );
  }

  // ── Realism Evals (step 10: the 5 realism evaluation calls — relationship, emotional, physical, narrative, one-shot) ──
  // Plain leaf sibling to LlmEvalEngine. Owns the 5 eval prompt builders + call orchestration + parse for realism results
  // (bond/trust/emotion/arousal/fixation/spatial stance/time + pending for chips/reasons) + side effects (apply deltas on
  // rel/nsfw, set emotion scalars, updateFixation, setObjective thin for autonomous, snapshot in oneShot).
  // Depends on llm_eval_engine for fire/strip/extract cbs (wired via god thins for centralization).
  // Some coordination (setObjective thin for proposal, physical posture delegate to timeService) stayed thin/coordinated
  // per precedent (qualify).
  // ChatService owns via late final (after engine) + thins/delegates at *every* prior call site for the 5 _evaluate*Call
  // (full excision of moved code from engine + prior thin bodies).
  // 0 @Deprecated shims. 0 new god private _ methods (thins stay in god as the public surface; void _ count grep stays 15
  // confirmed after every edit + final; +1 late final + thins/calls + reset comment syncs only per plan).
  // Stateless/prompt-only: no reset calls needed. See expanded "keep reset blocks in sync" comments at *all* ~15+ sites
  // (see CLAUDE.md full list + incomplete zeroing hygiene; buffer removal complete)
  // zeroing of secondary config on group/0-session/new-chat now complete"; both startNew branches explicit; cross-refs
  // e.g. setActiveCharacter:1572).
  // 1:1 vs group + oneShot vs normal + Realism/Needs/Objectives parity 1:1 equivalent deltas/behavior at all times
  // (cbs + god's impersonation dance + load/saveScalarsIntoGroupRealism before speaker evals; qualified; exercised in
  // dedicated + key suites + manual).
  // aug exercising only passive/qualified (no realism-evals-specific aug file edits; full in dedicated
  // realism_evals_test + manual; exercised via god thins _evaluate*Call ; qualified notes only in dedicated header + god
  // + MD per precedent).
  // Realism Verification (Director/Verifier) — new optional leaf (plan 2026-04).
  // late final after _llmEvalEngine (for dep on fire/strip/extract + state cbs; before evals/impact so they can receive the cb in their ctors).
  // Granular cbs only (live closures for group impersonation + test). Receives *full* latent bundle from callers (the two leaves assemble prompt/pre/char/scene/raw/kind/strict/max at their fire sites).
  // 0 new god void _ (thins + this late final + god-owned _isVerifying* + getters only).
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
      setPendingRealismMetadata: (v) => _pendingRealismMetadata = v,
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
      // Tools transport (realism_tools.dart): same door + probe memory the
      // Journal and Growth passes use, so a backend answers the "can you speak
      // tools?" question at most once per run across all three systems.
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      isEvalCancelled: () => _isCancellingRealismEval || _realismEvalCancelled,
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
      setPendingRealismMetadata: (v) => _pendingRealismMetadata = v,
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

  // ── Objective Proposal (step 11: proposal path support + generateObjectiveTasks + _checkTaskCompletionInBackground) ──
  // Plain leaf sibling to LlmEvalEngine (and realism_evals). Owns generateObjectiveTasks
  // (2000 + central strip via cb for thinking models) + checkTaskCompletionInBackground
  // (2000 + strip; task vs taskless) + internal prompt/parse.
  // The autonomous "none" vs value + dedup + autoGenerateTasks:true only for autonomous
  // lives in realism_evals (narr/oneShot); correct target under group impersonation via
  // god dance + live cbs; objective mgmt (setObjective, load/save/deact, tasksFor,
  // isChecking, _activeObjectives, markTaskCompleted) stay thin/coordinated in god per plan
  // (qualify; "thin delegation here; full objective proposal in step 11").
  // ChatService owns via late final (after _realismEvals) + thins/delegates at *every*
  // prior call site for generate + _check (full excision from engine + old thin bodies).
  // 0 @Deprecated shims. 0 new god private _ methods (thins as public surface; void _
  // count grep stays 15 confirmed after every edit + final; +1 late final + thins/calls
  // + reset comment syncs only per plan).
  // Stateless/prompt-only: no reset calls needed. See "keep reset blocks in sync" + "incomplete zeroing now complete" + authority (simple model+Director) + full leaf list in CLAUDE.md (both startNew; cross-refs e.g. setActiveCharacter:1572).
  // 1:1 vs group + oneShot/normal parity for proposed "none"/value + dedup + auto only
  // autonomous + correct target (even under impersonation; decision/attach via dance, gen prompt read best-effort/timing-dep as qualified in leaf + test + impersonation finally); task vs taskless (mark cb mutation in god for task auto); 2000+central
  // strip; dispatch preserved via cbs + god impersonation. (Fix round 2 updates: timing qualify, zeroing of _isChecking + messagesSince now explicit at all sites + "now complete", mark cb, getPrimary del as dead, test bodies 11 post del, lints 0, claims updated only post re-gates/re-reads).
  // aug exercising only passive/qualified (no objective-proposal-specific aug file edits;
  // full in dedicated objective_proposal_test + manual; exercised via god thins
  // generate/check ; qualified notes only in dedicated header + god + MD per precedent).
  ObjectiveProposal _buildObjectiveProposal() {
    return ObjectiveProposal(
      stripThinkBlocks: _stripThinkBlocks,
      getLlmService: () =>
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService,
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
      // The completion check runs pre-generation; the flags are consumed by
      // _maybeRunJournalPass/_maybeRunGrowthPass post-generation (a finished
      // quest is a story beat worth journaling AND a moment characters grow).
      onObjectiveCompleted: () {
        // Same shared rate limiter as onSalienceKick (salience_kick_gate.dart)
        // — a completed quest in the middle of an emotionally hot scene must
        // not stack a second immediate double-pass on the one just fired.
        if (!_growthService.salienceKickGate.allow(
          sessionId: _currentSessionId,
          messageCount: _messages.length,
        )) {
          debugPrint(
            '[Journal] objective-completed kick suppressed — within '
            '$kSalienceKickMinGapMessages messages of the last one',
          );
          return;
        }
        _journalMaintenance.eventKickPending = true;
        _growthService.eventKickPending = true;
      },
      // Ambitions (Living Time §6): a whole quest finishing is the ONE moment
      // ambition progress can move. Fire-and-forget; owner resolved from the
      // objective row's characterId (per-character in groups by construction).
      onQuestAchieved: (obj) {
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

  /// Tool-calling door shared by both background passes: same eval posture
  /// as _fireLLMEval (low temp, reasoning off). All backends probe — local
  /// KoboldCpp included (Qwen3 etc. call tools fine); incapable models fall
  /// back to the XML floor.
  Future<LlmToolResponse?> _fireToolEval(
    String prompt,
    List<Map<String, dynamic>> tools,
  ) async {
    final service =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;
    // [EvalTraffic]: the tool name is the label — free and precise on this
    // lane, where every call carries its schema.
    final trafficWatch = Stopwatch()..start();
    void recordTraffic(LlmToolResponse? resp) => EvalTraffic.current.record(
      label:
          ((tools.firstOrNull?['function'] as Map?)?['name'] as String?) ??
          'tool',
      lane: 'tools',
      promptChars: prompt.length,
      outputChars: resp == null
          ? 0
          : resp.text.length +
                resp.calls.fold(0, (a, c) => a + c.arguments.length * 16),
      ms: trafficWatch.elapsedMilliseconds,
    );
    try {
      final resp = await service
          .generateWithTools(
            GenerationParams(
              prompt: prompt,
              maxLength: 4000,
              temperature: 0.1,
              repeatPenalty: 1.15,
              topP: 0.5,
              xtcProbability: 0.0,
              reasoningEnabled: false,
              // Explicit thinking-off: Nano-GPT/OpenRouter only receive the
              // disable signal when the reasoning block is present, and it is
              // only emitted when a reasoning field is set. Without this a
              // ":thinking" model (e.g. Kimi K2.6) keeps reasoning during the
              // journal tool call, which returns tool calls only intermittently
              // (the "had to regen twice" symptom). 0 → {enabled:false,
              // max_tokens:0, exclude:true}, the strongest disable signal.
              reasoningMaxTokens: 0,
              // Keep the think channel on mandatory models so a 400-then-
              // exclude path cannot swallow the JSON / tool call (Kimi 2.6).
              salvageReasoning: true,
              stopSequences: const [],
            ),
            tools,
            // Whole-call deadline: a backend that accepts the request and never
            // answers (cold model reload after an idle unload, dead server queue,
            // or the call queued behind a long generation like character
            // creation) must not park a journal/realism pass forever. The timeout
            // THROWS — isToolTransportFailure classifies it so verdict sites fall
            // back to text for the round without branding the backend XML-only.
          )
          .timeout(kEvalToolCallTimeout);
      recordTraffic(resp);
      return resp;
    } on TimeoutException {
      // The deadline abandoned an in-flight call. On the single-slot local
      // backend that orphan holds the shared idle slot (_pendingRequest), so
      // waitForIdle callers — text evals, the Scene Guest mint — would hang
      // behind it indefinitely; tear it down. (If the server is hung on the
      // orphan, the server-side abort also frees anything queued behind it.)
      // Remote backends don't serialize on the slot — nothing to release.
      if (service is KoboldService) service.abortGeneration();
      // The wall time was spent whether or not an answer came back.
      recordTraffic(null);
      rethrow;
    }
  }

  /// Backend+model identity key for the tools probe. Remote model name AND
  /// local model path both ride the key, so switching either re-probes tool
  /// support (capability is per model).
  String get _evalBackendIdentity {
    final service =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;
    return '${service.backendName}|${_storageService.remoteModelName}'
        '|${_storageService.lastUsedModelPath ?? ''}';
  }

  /// Active tool-support prober behind the sidebar's tool-calling pill:
  /// verdicts land on the same [_toolProbe] the passes use, auto-retests on
  /// backend/model switches, and backs the pill's tap-to-retest.
  ToolSupportTester _buildToolSupportTester() {
    return ToolSupportTester(
      probe: _toolProbe,
      fireToolEval: _fireToolEval,
      getBackendIdentity: () => _evalBackendIdentity,
      isBackendReady: () =>
          (testLlmServiceOverride ??
                  _llmProvider?.activeService ??
                  _koboldService)
              .isReady,
      isBusy: () => _isGenerating,
      onNotify: notifyListeners,
      // OpenRouter/Nano-GPT list tool support in their /models metadata, so the
      // auto-test seeds the probe for free instead of pinging the model. Gated
      // to the openRouter backend: oMLX runs at localhost (no metadata) and the
      // resolver returns null for any non-metadata host anyway — those, like
      // local backends, keep the runtime ping.
      fetchMetadataToolVerdict: () async {
        if (_llmProvider?.activeBackend != BackendType.openRouter) return null;
        final caps = await VisionSupportResolver.instance.capabilitiesForRemote(
          apiUrl: _storageService.remoteApiUrl,
          apiKey: _storageService.remoteApiKey,
          modelName: _storageService.remoteModelName,
        );
        return caps?.toolCalling;
      },
    );
  }

  /// The current model's tool-calling verdict (sidebar pill + web facade).
  ToolCallSupport get toolCallSupport => _toolSupportTester.current;
  bool get isTestingToolSupport => _toolSupportTester.isTesting;

  /// Re-probe the current backend+model's tool support (pill tap).
  Future<void> testToolCalling() => _toolSupportTester.test(force: true);
}
