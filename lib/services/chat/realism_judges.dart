// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/chat/with_user_eval.dart';
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolResponse;

/// The text-eval door (worker lane, low temperature, reasoning off).
typedef RealismTextEval =
    Future<String?> Function(
      String prompt, {
      void Function(String)? onChunk,
      double repeatPenalty,
      String label,
    });

/// The pre-generation judges and their dispatch, the trust-repair
/// substitute, the batched Director verification, and the post-reply
/// with-user glance.
///
/// The judges score the USER's message and fire before generation; 1:1
/// regen and the group dance share [runPreGenJudges] so a restored
/// trust-repair latch cannot skip the repair branch on one path. The three
/// prefix-sharing judges dispatch in a fixed order so KoboldCpp's FIFO
/// queue serves them consecutively (see [_fireStaggeredRealismEvals]).
class RealismJudges {
  RealismJudges(
    this._scope, {
    required this.realismEvals,
    required this.verifier,
    required this.fireLLMEval,
    required this.fireToolEval,
    required this.toolProbe,
    required this.backendIdentity,
    required this.writePending,
    required this.evalCancelled,
    required this.oneShotActive,
    required this.personaName,
    required this.dispatchStagger,
  });

  final RealismScope _scope;
  final RealismEvals Function() realismEvals;
  final RealismVerification Function() verifier;
  final RealismTextEval fireLLMEval;
  final Future<LlmToolResponse?> Function(ToolEvalSpec spec) fireToolEval;
  final ToolTransportProbe toolProbe;
  final String Function() backendIdentity;

  /// Pending writes that can become salient go through here (Growth kick).
  final void Function(Map<String, dynamic>? value) writePending;
  final bool Function() evalCancelled;
  final bool Function() oneShotActive;
  final String Function() personaName;

  /// Inter-call delay that keeps the staggered judges in wire order.
  final Duration dispatchStagger;

  RealismEvals get _realismEvals => realismEvals();
  RealismVerification get _realismVerifier => verifier();
  bool get _realismEnabled => _scope.realismEnabled();
  bool get _realismEvalCancelled => evalCancelled();
  bool get _oneShotActive => oneShotActive();
  CharacterCard? get _activeCharacter => _scope.activeCharacter();
  GroupChat? get _activeGroup => _scope.activeGroup();
  List<ChatMessage> get _messages => _scope.messages;
  RelationshipService get _relationshipService => _scope.relationship();
  Map<String, dynamic>? get _pendingRealismMetadata => _scope.pending();
  set _pendingRealismMetadata(Map<String, dynamic>? v) => _scope.setPending(v);
  void _writePendingRealismMetadata(Map<String, dynamic>? v) => writePending(v);
  String get _evalBackendIdentity => backendIdentity();
  ToolTransportProbe get _toolProbe => toolProbe;
  Future<LlmToolResponse?> _fireToolEval(ToolEvalSpec spec) =>
      fireToolEval(spec);
  Future<void> _saveChat() => _scope.saveChat();
  void notifyListeners() => _scope.notify();

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
      final raw = await fireLLMEval(
        prompt,
        onChunk: onChunk,
        label: 'trust_repair',
      );
      if (raw == null) return;

      final text = stripEvalThinkBlocks(raw).trim();

      final verdictMatch = RegExp(
        r'"verdict"\s*:\s*"([^"]+)"',
      ).firstMatch(text);

      final recovery = (evalJsonInt(text, 'trust_recovery') ?? 0).clamp(0, 60);
      final verdict = verdictMatch?.group(1) ?? 'rejected';
      final reason = evalJsonString(text, 'reason') ?? '';

      if (recovery > 0) {
        _relationshipService.applyTrustDelta(recovery);
        debugPrint(
          '[Realism:TrustRepair] $verdict — recovered $recovery → ${_relationshipService.trustLevel} ($reason)',
        );
      } else {
        debugPrint('[Realism:TrustRepair] Rejected — no recovery ($reason)');
      }

      // Surface verdict in message metadata so swipe history can record it
      _writePendingRealismMetadata({
        ...?_pendingRealismMetadata,
        'trust_repair_verdict': verdict,
        'trust_repair_recovery': recovery,
        if (reason.isNotEmpty) 'trust_repair_reason': reason,
      });

      _saveChat();
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:TrustRepair] Failed: $e');
    }
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
      _realismEvals.evaluateRelationshipCall(onChunk: onChunk),
      Future.delayed(
        dispatchStagger,
        () => _realismEvals.evaluateEmotionalStateCall(onChunk: onChunk),
      ),
      Future.delayed(
        dispatchStagger * 2,
        () => _realismEvals.evaluateNarrativeCall(onChunk: onChunk),
      ),
    ]);
  }

  /// Shared pre-gen judge dispatch for the dance AND 1:1 regen so a restored
  /// trust-repair latch cannot skip the repair branch on one path.
  Future<void> runPreGenJudges({
    required void Function(String) onChunk,
    String? logSpeakerName,
  }) async {
    if (_relationshipService.pendingTrustRepair) {
      debugPrint(
        '[Realism:Unified] Trust-repair eval'
        '${logSpeakerName != null ? ' for $logSpeakerName' : ''} '
        '+ remaining judges (not a full freeze)',
      );
      _relationshipService.consumePendingTrustRepair();
      final userText = _messages
          .lastWhere(
            (m) => m.isUser,
            orElse: () => ChatMessage(text: '', sender: '', isUser: true),
          )
          .text;
      await _evaluateTrustRepairCall(userText, onChunk: onChunk);
      if (_realismEvalCancelled) return;
      await _runBatchedRealismVerification(
        () => _fireTrustRepairRemainingEvals(onChunk),
      );
      return;
    }
    if (_oneShotActive) {
      debugPrint(
        '[Realism:Unified] One-shot eval'
        '${logSpeakerName != null ? ' for $logSpeakerName' : ''}',
      );
      await _realismEvals.evaluateOneShotCall(onChunk: onChunk);
      return;
    }
    debugPrint(
      '[Realism:Unified] 3-call eval + verifier'
      '${logSpeakerName != null ? ' for $logSpeakerName' : ''}',
    );
    await _runBatchedRealismVerification(
      () => _fireStaggeredRealismEvals(onChunk),
      logSpeakerName: logSpeakerName,
    );
  }

  /// Emotion + narrative only — the remaining judges after a trust-repair
  /// relationship substitute (audit P1.11). Scene-time is post-generation.
  Future<void> _fireTrustRepairRemainingEvals(
    void Function(String) onChunk,
  ) async {
    await Future.wait([
      _realismEvals.evaluateEmotionalStateCall(onChunk: onChunk),
      Future.delayed(
        dispatchStagger,
        () => _realismEvals.evaluateNarrativeCall(onChunk: onChunk),
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
  Future<void> runWithUserPass(String reply) async {
    if (!_realismEnabled) return;
    if (reply.trim().isEmpty) return;
    final speaker = _activeCharacter;
    if (speaker == null) return;
    final userName = personaName().trim();
    final verdict = await makeWithUserEval().detect(
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

  WithUserEval makeWithUserEval() => WithUserEval(
    fire: ({required debugLabel, required tools, required buildPrompt}) async {
      return fireStructuredEval(
        probe: _toolProbe,
        backendIdentity: _evalBackendIdentity,
        debugLabel: debugLabel,
        tools: tools,
        buildPrompt: buildPrompt,
        callToText: (resp) =>
            realismToolCallToJson(WithUserEval.kWithUserTool, resp.calls),
        fireToolEval: _fireToolEval,
        toolChoice: WithUserEval.kWithUserTool,
        getPreferTextEvals: () => _scope.realismSettings().preferTextEvals,
        fireTextEval: (p, {onChunk}) => fireLLMEval(
          p,
          repeatPenalty: kScalarEvalRepeatPenalty,
          label: 'with_user',
        ),
      );
    },
  );
}
