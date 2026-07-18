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
  }) => _llmEvalEngine.fireLLMEval(prompt, onChunk: onChunk);

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
  // (_kEvalDispatchStagger lives on the ChatService class body; see note there.)

  Future<void> _evaluateRelationshipCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateRelationshipCall(onChunk: onChunk);

  Future<void> _evaluateEmotionalStateCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateEmotionalStateCall(onChunk: onChunk);

  Future<void> _evaluatePhysicalStateCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluatePhysicalStateCall(onChunk: onChunk);

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

    if (_activeCharacter == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
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
      final raw = await _fireLLMEval(prompt, onChunk: onChunk);
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
      'moodDecayCounter': _moodDecayCounter,
      'characterEmotion': _characterEmotion,
      'emotionIntensity': _emotionIntensity,
      'timeOfDay': _timeService.timeOfDay,
      'dayCount': _timeService.dayCount,
      'startDayOfWeek': _timeService.startDayOfWeekAnchor,
      'arousalLevel': _nsfwService.arousalLevel,
      'cooldownTurnsRemaining': _nsfwService.cooldownTurnsRemaining,
      'cooldownTurnsTotal': _nsfwService.cooldownTurnsTotal,
      'trustLevel': _relationshipService.trustLevel,
      'activeFixation': _relationshipService.activeFixation,
      'fixationLifespan': _relationshipService.fixationLifespan,
      'spatialStance': _relationshipService.spatialStance,
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
  /// Fire the four realism eval calls (relationship / emotional / physical /
  /// narrative) concurrently with the standard dispatch stagger. This exact
  /// 4-call block was duplicated byte-for-byte in the centralized 1:1 path and
  /// the per-speaker group path; sharing it is the first DRY step toward a single
  /// eval path. The caller decides whether to wrap it in batched verification
  /// (`beginCollect`/`finalize`) — that wrapping currently differs between the
  /// two paths and is deliberately left to the caller until that divergence is
  /// reconciled.
  Future<void> _fireStaggeredRealismEvals(void Function(String) onChunk) async {
    await Future.wait([
      _evaluateRelationshipCall(onChunk: onChunk),
      Future.delayed(
        ChatService._kEvalDispatchStagger,
        () => _evaluateEmotionalStateCall(onChunk: onChunk),
      ),
      Future.delayed(
        ChatService._kEvalDispatchStagger * 2,
        () => _evaluatePhysicalStateCall(onChunk: onChunk),
      ),
      Future.delayed(
        ChatService._kEvalDispatchStagger * 3,
        () => _evaluateNarrativeCall(onChunk: onChunk),
      ),
    ]);
  }
}
