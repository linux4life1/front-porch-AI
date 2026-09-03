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

/// Realism eval plumbing — chance-time injection, LLM eval fire + think-block
/// stripping, the five eval-call wrappers, trust-repair, realism-state capture,
/// and staggered eval dispatch. Extracted verbatim (zero behaviour change).
extension ChatServiceRealismEvals on ChatService {
  /// Injects a Chance Time event into the character's response prompt.
  /// Placed AFTER the character name suffix for maximum recency weight.
  /// Consumed after one use (cleared after response generation).
  String _getChanceTimeInjection() {
    // Thin delegation (full in ChaosInjection per step 8; UI flags stayed in god per plan).
    return _chaosInjection.buildChanceTimeInjection();
  }

  // ── LLM Eval Thins (step 9; full in LlmEvalEngine) + Needs Impact Thins (consolidated) + Objective Proposal Thins (step 11) ──
  // 0 new god privates beyond required thin delegates (fire/strip/extract/evaluate* thins + _runPostGenNeedsChecks thin (consolidated to evaluator; the prior separate _check* bodies excised as dead/vestigial per task) + generate/_check thins for objective; void_ count 15; +1 late final); thins only (public surface for now per plan); objective proposal coordination + some
  // prompt/obj mgmt + post-gen needs orchestration (impersonation dance, pre/post group scalars, long-gen, metadata attach) stayed thin in god per plan (qualified in objective_proposal header + here + test + MD).
  // All call sites (5 firing points for realism evals now via realism_evals step 10, gen/check now via objective_proposal step 11, proposal, direct fire/strip/extract in eval paths, post-gen needs) now delegate; non-eval uses ... also route via these thins (centralized, no parallel).

  Future<String?> _fireLLMEval(
    String prompt, {
    void Function(String)? onChunk,
    double repeatPenalty = 1.15,
    String label = 'eval',
  }) => _llmEvalEngine.fireLLMEval(
    prompt,
    onChunk: onChunk,
    repeatPenalty: repeatPenalty,
    label: label,
  );

  String _stripThinkBlocks(String text) =>
      _llmEvalEngine.stripThinkBlocks(text);

  int? _extractJsonInt(String text, String key) =>
      _llmEvalEngine.extractJsonInt(text, key);

  bool? _extractJsonBool(String text, String key) =>
      _llmEvalEngine.extractJsonBool(text, key);

  // KoboldCpp receives HTTP requests in wire order via loopback.
  // A small stagger prevents TCP timing from reordering concurrent
  // eval dispatches, ensuring KoboldCpp's FIFO queue (which serializes
  // internally) processes evals in our intended order rather than
  // reverse or interleaved. Zero wall time added — KoboldCpp serializes
  // anyway, so the stagger just ensures already-in-flight ordering.
  // (_kEvalDispatchStagger is a library-top-level const in chat_service_defaults.dart.)

  Future<void> _evaluateRelationshipCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateRelationshipCall(onChunk: onChunk);

  Future<void> _evaluateEmotionalStateCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateEmotionalStateCall(onChunk: onChunk);

  /// [postureOnly] is the post-generation spatial pass — the same eval leaf,
  /// asked the one question that can only be answered once the reply exists.
  Future<void> _evaluatePhysicalStateCall({
    void Function(String)? onChunk,
    bool postureOnly = false,
    bool skipClockAdvance = false,
  }) => _realismEvals.evaluatePhysicalStateCall(
    onChunk: onChunk,
    postureOnly: postureOnly,
    skipClockAdvance: skipClockAdvance,
  );

  Future<void> _evaluateNarrativeCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateNarrativeCall(onChunk: onChunk);

  Future<void> _evaluateOneShotCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateOneShotCall(onChunk: onChunk);

  /// One-shot trust repair evaluator.
  ///
  /// Called automatically on the user's next message after a severe trust drop
  /// (≥ -20 delta). Replaces the normal relationship eval for that turn.
  /// The LLM weighs the explanation against character persona and chat history,
  /// returning a trust_recovery value (0–60). Recovery is capped to prevent
  /// instant restoration from Absolute Distrust.
  Future<void> _evaluateTrustRepairCall(
    String userExplanation, {
    void Function(String)? onChunk,
  }) async {
    if (!_realismEnabled || _activeCharacter == null) return;
    final charName = _activeCharacter!.name;
    final persona = _activeCharacter!.personality;
    final recentCount = _messages.length < 10 ? _messages.length : 10;
    final history = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    final prompt =
        'You are evaluating whether $charName should partially restore trust '
        'after a severe breach caused by the previous interaction.\n\n'
        'Character Persona: $persona\n\n'
        'Recent chat history (last ~10 messages):\n$history\n\n'
        'The user\'s trust-repair explanation is: "$userExplanation"\n\n'
        'Evaluate ONLY whether this explanation is convincing given:\n'
        '1. The character\'s personality — are they forgiving, stubborn, paranoid, naive?\n'
        '2. The plausibility of the explanation against the chat history\n'
        '3. Whether the explanation contradicts established facts\n\n'
        'Rules:\n'
        '- trust_recovery: 0 (rejected) to 60 (fully convincing)\n'
        '- Paranoid/skeptical characters: give 0–20 even for good explanations\n'
        '- Forgiving/naive characters: may give 30–60 for plausible explanations\n'
        '- Do NOT give 60 unless the explanation perfectly resolves the breach\n'
        '- "reason" must be 1 short sentence from the character\'s POV\n\n'
        'Respond with ONLY: {"trust_recovery": <0-60>, "verdict": "accepted|partial|rejected", "reason": "<brief>"}\n';

    try {
      debugPrint('[Realism:TrustRepair] Evaluating repair attempt...');
      final raw = await _fireLLMEval(
        prompt,
        onChunk: onChunk,
        label: 'trust_repair',
      );
      if (raw == null) return;

      final text = _stripThinkBlocks(raw).trim();

      final verdictMatch = RegExp(
        r'"verdict"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(text);

      final recovery = (_extractJsonInt(text, 'trust_recovery') ?? 0).clamp(
        0,
        60,
      );
      final verdict = verdictMatch?.group(1) ?? 'rejected';
      final reason = reasonMatch?.group(1) ?? '';

      if (recovery > 0) {
        _relationshipService.applyTrustDelta(recovery);
        debugPrint(
          '[Realism:TrustRepair] $verdict — recovered $recovery → ${_relationshipService.trustLevel} ($reason)',
        );
      } else {
        debugPrint('[Realism:TrustRepair] Rejected — no recovery ($reason)');
      }

      // Surface verdict in message metadata so swipe history can record it
      _pendingRealismMetadata = {
        ...?_pendingRealismMetadata,
        'trust_repair_verdict': verdict,
        'trust_repair_recovery': recovery,
        if (reason.isNotEmpty) 'trust_repair_reason': reason,
      };

      _saveChat();
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:TrustRepair] Failed: $e');
    }
  }

  Map<String, dynamic> _captureRealismState({Map<String, int>? preTurn}) {
    final state = {
      'affectionScore': _relationshipService.affectionScore,
      'relationshipTier': _relationshipService.relationshipTier,
      'longTermScore': _relationshipService.longTermScore,
      'longTermTier': _relationshipService.longTermTier,
      'turnsSinceLongTermCheck': _relationshipService.turnsSinceLongTermCheck,
      'shortTermDeltasSummary': _relationshipService.shortTermDeltasSummary,
      // The decay cadence + the group's hidden inter-character feelings. These
      // are the eval inputs that used to be missing from this snapshot, so a
      // group regen could not rewind them; see captureCadenceAndFeelings.
      // (They replaced 'moodDecayCounter', which was captured, persisted and
      // restored while no decay logic read it — the real counter was, and is,
      // RelationshipService's.)
      ..._relationshipService.captureCadenceAndFeelings(),
      'characterEmotion': _characterEmotion,
      'emotionIntensity': _emotionIntensity,
      'timeOfDay': _timeService.timeOfDay,
      'dayCount': _timeService.dayCount,
      'startDayOfWeek': _timeService.startDayOfWeekAnchor,
      'storyClock': _timeService.storyClockIso,
      'storyStartDate': _timeService.storyStartDateIso,
      'arousalLevel': _nsfwService.arousalLevel,
      'cooldownTurnsRemaining': _nsfwService.cooldownTurnsRemaining,
      'cooldownTurnsTotal': _nsfwService.cooldownTurnsTotal,
      'trustLevel': _relationshipService.trustLevel,
      'activeFixation': _relationshipService.activeFixation,
      'fixationLifespan': _relationshipService.fixationLifespan,
      'spatialStance': _relationshipService.spatialStance,
      'withUser': _relationshipService.withUser,
      // Pockets & Wardrobe rides the rewind contract like every other
      // per-turn scalar. Without this a regenerate re-runs the detection pass
      // on a NEW reply while the record still carries the discarded reply's
      // changes — she picks the keys up twice, or is left holding something
      // from a version of the scene that no longer exists. Found in review by
      // Grok, 2026-08-07, and required by the design doc in as many words.
      ...(() {
        final c = _activeCharacter;
        if (c == null) return const <String, dynamic>{};
        final p = pocketsFor(_getCharacterIdFromCard(c));
        return p == null ? const <String, dynamic>{} : {'pockets': p.toJson()};
      })(),
    };

    // Include needs snapshot when the simulation is active (clean port).
    // Note: 'enabled' is deliberately omitted from the per-message snapshot.
    // The enabled flag is authoritative from the character card / current session
    // (see setNeedsSimEnabled and ext seeding). Snapshots only carry the vector
    // for timeline continuity while the sim is on. This prevents historical
    // snapshots from resurrecting a stale enabled state after a mid-chat toggle-off.
    if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
      // Explicit <String, dynamic> for the needs snapshot so that 'deltas' (Map with
      // mixed int/String values from computeNeedsDeltasWithReasons) can be attached
      // without runtime generic value-type violation (the 'vector' entry statically
      // infers Map<String,int>, which would lock the literal's value type and reject
      // the deltas map on []=).
      final needsSnap = <String, dynamic>{
        'vector': Map<String, int>.from(_needsSimulation.vector),
      };
      state['needs'] = needsSnap;

      final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
        preTurn ?? const <String, int>{},
      );
      if (needsDeltas.isNotEmpty) {
        needsSnap['deltas'] = needsDeltas;
      }
    }

    return state;
  }

  // ── Phase 1: Per-character realism evaluation for the upcoming speaker ────
  /// Fire the three pre-generation judges (relationship / emotional /
  /// narrative) concurrently with the standard dispatch stagger. Scene-time
  /// is a reply-reader now — it fires after generation, like posture.
  Future<void> _fireStaggeredRealismEvals(void Function(String) onChunk) async {
    // Dispatch order is a caching decision (maintainer, 2026-08-10: firing
    // order is free; eval PHASE is not for the judges). Relationship,
    // emotional and narrative open with the byte-identical judgePrefix, so
    // on KoboldCpp's FIFO queue the first pays the prefill and the next two
    // fast-forward through it — but only if they arrive CONSECUTIVELY.
    // (test/services/chat/realism_shared_prefix_test.dart pins the prefix
    // and this order.)
    await Future.wait([
      _evaluateRelationshipCall(onChunk: onChunk),
      Future.delayed(
        _kEvalDispatchStagger,
        () => _evaluateEmotionalStateCall(onChunk: onChunk),
      ),
      Future.delayed(
        _kEvalDispatchStagger * 2,
        () => _evaluateNarrativeCall(onChunk: onChunk),
      ),
    ]);
  }

  /// Emotion + narrative only — the remaining judges after a trust-repair
  /// relationship substitute (audit P1.11). Scene-time is post-generation.
  Future<void> _fireTrustRepairRemainingEvals(
    void Function(String) onChunk,
  ) async {
    await Future.wait([
      _evaluateEmotionalStateCall(onChunk: onChunk),
      Future.delayed(
        _kEvalDispatchStagger,
        () => _evaluateNarrativeCall(onChunk: onChunk),
      ),
    ]);
  }

  /// beginCollect → [fireEvals] → finalize → verifyBatch → apply.
  ///
  /// The three multi-call sites (dance normal, dance trust-repair remainder,
  /// regen) share this so the item-map / verifier wiring cannot drift
  /// (second-look).
  Future<void> _runBatchedRealismVerification(
    Future<void> Function() fireEvals, {
    String? logSpeakerName,
  }) async {
    _realismEvals.beginCollectForBatchedVerification();
    await fireEvals();
    await _realismEvals.finalizeBatchedRealismVerifications();
    final collected = _realismEvals.getCollectedForBatch();
    if (collected.isEmpty) return;
    if (logSpeakerName != null) {
      debugPrint(
        '[Realism:Unified] Verifying ${collected.length} eval(s) for '
        '$logSpeakerName',
      );
    }
    final items = collected
        .map(
          (p) => (
            evalKind: p['kind'] as String,
            rawOutput: p['raw'] as String,
            sceneResponse: p['scene'] as String,
            preState: null,
            activeChar: _activeCharacter,
            activeGroup: _activeGroup,
            recentMessages: _messages,
            promptText: p['prompt'] as String?,
            injections: (p['injections'] as Map?)?.cast<String, String>(),
            strictnessOverride: null,
            maxPassesOverride: null,
          ),
        )
        .toList();
    final batchRes = await _realismVerifier.verifyBatch(items);
    await _realismEvals.applyBatchResults(batchRes);

    // The Director's receipt. Every eval on this path defers to the batch and
    // returns BEFORE the per-eval wrapper that normally stamps the chip
    // (_verifyAndApply), so with the feature on the deltas were quietly
    // corrected and the user was shown nothing — the chip only ever appeared
    // in one-shot mode. One summary for the turn: corrected wins over
    // accepted, with the corrections' reasons in the tooltip.
    if (batchRes.isNotEmpty &&
        _realismVerifier.getRealismVerificationEnabled()) {
      final corrected = batchRes.values.where((v) => v.status == 'corrected');
      final passes = batchRes.values.fold<int>(
        0,
        (m, v) => v.passes > m ? v.passes : m,
      );
      final reasons = corrected
          .map((v) => v.reason)
          .where((r) => r.isNotEmpty)
          .join('; ');
      // Built through the same factories the single-eval path stamps, so the
      // metadata shape cannot drift from what the bubble reads (correctedRaw
      // is unused here — only toMetadata() is).
      final summary = corrected.isEmpty
          ? VerificationResult.accepted(raw: '', passes: passes)
          : VerificationResult.corrected(
              raw: '',
              passes: passes,
              reason: reasons,
            );
      _pendingRealismMetadata = {
        ...?_pendingRealismMetadata,
        RealismVerification.kMetaKey: summary.toMetadata(),
      };
    }
  }

  /// Glance bit only. Runs AFTER posture so it can read the stance that
  /// pass just wrote. Never writes spatial stance.
  Future<void> _runWithUserPass(String reply) async {
    if (!_realismEnabled) return;
    if (reply.trim().isEmpty) return;
    final speaker = _activeCharacter;
    if (speaker == null) return;
    final userName = _userPersonaService.persona.name.trim();
    final verdict =
        await WithUserEval(
          fire:
              ({
                required debugLabel,
                required tools,
                required buildPrompt,
              }) async {
                return fireStructuredEval(
                  probe: _toolProbe,
                  backendIdentity: _evalBackendIdentity,
                  debugLabel: debugLabel,
                  tools: tools,
                  buildPrompt: buildPrompt,
                  callToText: (resp) => realismToolCallToJson(
                    WithUserEval.kWithUserTool,
                    resp.calls,
                  ),
                  fireToolEval: _fireToolEval,
                  toolChoice: WithUserEval.kWithUserTool,
                  getPreferTextEvals: () =>
                      _storageService.realismSettings.preferTextEvals,
                  fireTextEval: (p, {onChunk}) => _fireLLMEval(
                    p,
                    repeatPenalty: kScalarEvalRepeatPenalty,
                    label: 'with_user',
                  ),
                );
              },
        ).detect(
          charName: speaker.name,
          userName: userName.isEmpty ? 'the user' : userName,
          reply: clampEvalMessage(reply),
          recentExchange: recentExchange(_messages),
          stance: _relationshipService.spatialStance,
        );
    _relationshipService.applyWithUserVerdict(verdict);
    debugPrint(
      '[Presence] with_user=$verdict '
      '(glance=${_relationshipService.withUser})',
    );
  }
}
