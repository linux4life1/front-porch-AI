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
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/needs_impact_zero.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart'
    show
        kMinRelationshipDelta,
        kMaxRelationshipDelta,
        kMinTrustDelta,
        kMaxTrustDelta,
        kMinArousalDelta,
        kMaxArousalDelta;

part 'realism_verification_rules.dart';

/// Plain leaf for optional Realism Verification (Director/Verifier). Ingests latent; rules+reprocess. Cbs; stateless (CLAUDE.md). 495 LOC (wc+re-read post trims+fmt+braces+deletions). void_=15. aug passive. Per rules.
class RealismVerification {
  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })
  fireLLMEval;
  final String Function(String) stripThinkBlocks;
  final int? Function(String text, String key) extractJsonInt;
  final bool? Function(String text, String key) extractJsonBool;

  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;
  final String Function() getUserName;
  final List<ChatMessage> Function() getMessages;
  final bool Function() getRealismVerificationEnabled;
  final int Function() getVerificationMaxReprocesses;
  final int Function() getVerificationStrictness;

  // Pre-turn / latent cbs (exact context from engine).
  final Map<String, dynamic> Function({Map<String, int>? preTurn})?
  captureRealismState;
  final Map<String, int> Function()? getPreTurnNeedsVector;
  final String Function()? getCurrentSpeakerIdForRealism;

  // Overlay phase + cancel (god wired).
  final void Function(bool verifying, {int pass, int max})? onVerificationPhase;
  final bool Function()? isCancelling;

  RealismVerification({
    required this.fireLLMEval,
    required this.stripThinkBlocks,
    required this.extractJsonInt,
    required this.extractJsonBool,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getUserName,
    required this.getMessages,
    required this.getRealismVerificationEnabled,
    required this.getVerificationMaxReprocesses,
    required this.getVerificationStrictness,
    this.captureRealismState,
    this.getPreTurnNeedsVector,
    this.getCurrentSpeakerIdForRealism,
    this.onVerificationPhase,
    this.isCancelling,
  });

  static const String kMetaKey = 'realism_verification';

  Future<VerificationResult> verify({
    required String evalKind,
    required String rawOutput,
    required String sceneResponse,
    Map<String, dynamic>? preState,
    CharacterCard? activeChar,
    GroupChat? activeGroup,
    List<ChatMessage>? recentMessages,
    String? promptText,
    Map<String, String>? injections,
    int? strictnessOverride,
    int? maxPassesOverride,
  }) async {
    final enabled = getRealismVerificationEnabled();
    if (!enabled) {
      return VerificationResult.accepted(raw: rawOutput, passes: 0);
    }

    final char = activeChar ?? getActiveCharacter();
    final group = activeGroup ?? getActiveGroup();
    final messages = recentMessages ?? getMessages();
    final strict = strictnessOverride ?? getVerificationStrictness();
    final maxP = maxPassesOverride ?? getVerificationMaxReprocesses();

    // Rich latent bundle for proper (not shallow) judgement:
    // prompt + injections + pre scalars/vector + scene + char (name/personality/scenario/frontPorch) +
    // group context + kind + raw + strict/max.
    final bundle = <String, dynamic>{
      'eval_kind': evalKind,
      'raw': rawOutput,
      'scene': sceneResponse,
      'pre_state': preState ?? (captureRealismState?.call() ?? {}),
      'prompt': promptText ?? '',
      'injections': injections ?? const <String, String>{},
      'char_name': char?.name ?? '',
      'char_personality': char?.personality ?? '',
      'char_scenario': char?.scenario ?? '',
      'char_frontPorch': char?.frontPorchExtensions?.toJson() ?? {},
      'group': group != null ? {'name': group.name} : null,
      'recent': messages.length,
      'strictness': strict,
      'max_passes': maxP,
      'user': getUserName(),
      'speaker_id': getCurrentSpeakerIdForRealism?.call() ?? '',
    };

    debugPrint(
      '[Realism:Verifier] start kind=$evalKind enabled=$enabled strict=$strict max=$maxP',
    );
    onVerificationPhase?.call(true, pass: 0, max: maxP);

    final rule = _applyRuleChecks(rawOutput, bundle, strict);
    if (rule.passed) {
      onVerificationPhase?.call(false);
      return VerificationResult.accepted(raw: rawOutput, passes: 0);
    }

    String currentRaw = rule.correctedRaw ?? rawOutput;
    String reason = rule.reason;
    int passesUsed = 0;

    while (passesUsed < maxP) {
      if (isCancelling?.call() ?? false) {
        onVerificationPhase?.call(false);
        break;
      }
      passesUsed++;
      onVerificationPhase?.call(true, pass: passesUsed, max: maxP);

      final critiquePrompt = _buildReprocessCritiquePrompt(
        originalRaw: rawOutput,
        reason: reason,
        suggested: currentRaw,
        bundle: bundle,
        strict: strict,
      );

      String? reOut;
      try {
        reOut = await fireLLMEval(critiquePrompt);
        if (reOut != null) reOut = stripThinkBlocks(reOut);
      } catch (e) {
        debugPrint('[Realism:Verifier] re-fire fail $passesUsed: $e');
        break;
      }
      if (isCancelling?.call() ?? false) {
        onVerificationPhase?.call(false);
        break;
      }
      if (reOut == null || reOut.trim().isEmpty) break;

      // Overlay, then rule-check the MERGE. A rewrite that omits
      // relationship_delta used to pass as 0 and replace the original.
      final merged = mergeEvalJson(currentRaw, reOut);
      final reRule = _applyRuleChecks(merged, bundle, strict);
      currentRaw = reRule.correctedRaw ?? merged;
      reason = reRule.reason.isNotEmpty ? reRule.reason : 'reprocessed';
      if (reRule.passed) {
        onVerificationPhase?.call(false);
        return VerificationResult.corrected(
          raw: currentRaw,
          passes: passesUsed,
          reason: reason,
        );
      }
    }

    onVerificationPhase?.call(false);
    return VerificationResult.corrected(
      raw: currentRaw,
      passes: passesUsed,
      reason: reason,
    );
  }

  /// Batch version for "one director pass after all 5 (or 4) mains".
  /// Does local rule checks for every item (zero LLM cost).
  /// If any fail rules or strictness, builds ONE combined critique prompt with all
  /// the failing raws + their full latent bundles, fires the LLM once, and returns
  /// per-kind corrected (or accepted) results.
  /// This directly implements the user's suggestion and cuts verifier roundtrips
  /// from up to 5 to at most 1 when the feature is active on remote APIs.
  Future<Map<String, VerificationResult>> verifyBatch(
    List<
      ({
        String evalKind,
        String rawOutput,
        String sceneResponse,
        Map<String, dynamic>? preState,
        CharacterCard? activeChar,
        GroupChat? activeGroup,
        List<ChatMessage>? recentMessages,
        String? promptText,
        Map<String, String>? injections,
        int? strictnessOverride,
        int? maxPassesOverride,
      })
    >
    items,
  ) async {
    if (items.isEmpty) return {};

    final enabled = getRealismVerificationEnabled();
    if (!enabled) {
      return {
        for (final i in items)
          i.evalKind: VerificationResult.accepted(raw: i.rawOutput, passes: 0),
      };
    }

    final results = <String, VerificationResult>{};
    final needing = <int>[]; // indices into items that need LLM critique

    for (int idx = 0; idx < items.length; idx++) {
      final it = items[idx];
      final bundle = <String, dynamic>{
        'eval_kind': it.evalKind,
        'raw': it.rawOutput,
        'scene': it.sceneResponse,
        'pre_state': it.preState ?? (captureRealismState?.call() ?? {}),
        'prompt': it.promptText ?? '',
        'injections': it.injections ?? const <String, String>{},
        'char_name': (it.activeChar ?? getActiveCharacter())?.name ?? '',
        'char_personality':
            (it.activeChar ?? getActiveCharacter())?.personality ?? '',
        'char_scenario':
            (it.activeChar ?? getActiveCharacter())?.scenario ?? '',
        'char_frontPorch':
            (it.activeChar ?? getActiveCharacter())?.frontPorchExtensions
                ?.toJson() ??
            {},
        'group': {'name': (it.activeGroup ?? getActiveGroup())?.name ?? ''},
        'recent': (it.recentMessages ?? getMessages()).length,
        'strictness': it.strictnessOverride ?? getVerificationStrictness(),
        'max_passes': it.maxPassesOverride ?? getVerificationMaxReprocesses(),
        'user': getUserName(),
      };

      final rule = _applyRuleChecks(
        it.rawOutput,
        bundle,
        it.strictnessOverride ?? getVerificationStrictness(),
      );
      if (rule.passed) {
        results[it.evalKind] = VerificationResult.accepted(
          raw: it.rawOutput,
          passes: 0,
        );
      } else {
        needing.add(idx);
        results[it.evalKind] = VerificationResult.corrected(
          raw: rule.correctedRaw ?? it.rawOutput,
          passes: 0,
          reason: rule.reason,
        );
      }
    }

    if (needing.isEmpty) return results;

    onVerificationPhase?.call(
      true,
      pass: 1,
      max: getVerificationMaxReprocesses(),
    );

    // One combined critique for all that needed it.
    final critiquePrompt = _buildBatchCritiquePrompt(
      items: needing.map((i) => items[i]).toList(),
      initialCorrections: results,
    );

    String? reOut;
    try {
      reOut = await fireLLMEval(critiquePrompt);
      if (reOut != null) reOut = stripThinkBlocks(reOut);
    } catch (e) {
      debugPrint('[Realism:Verifier] batch re-fire fail: $e');
      onVerificationPhase?.call(false);
      return results;
    }

    if (reOut == null || reOut.trim().isEmpty) {
      onVerificationPhase?.call(false);
      return results;
    }

    // The model is instructed to return a flat JSON with keys = evalKind and values = the corrected raw for that kind.
    try {
      final noFence = reOut
          .replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ')
          .trim();
      final si = noFence.indexOf('{');
      final ei = noFence.lastIndexOf('}');
      if (si >= 0 && ei > si) {
        final obj = jsonDecode(noFence.substring(si, ei + 1));
        if (obj is Map) {
          for (final entry in obj.entries) {
            final k = entry.key.toString();
            final v = switch (entry.value) {
              final Map m => jsonEncode(m),
              final String s => s,
              null => '',
              final other => other.toString(),
            };
            if (results.containsKey(k) && v.isNotEmpty) {
              results[k] = VerificationResult.corrected(
                raw: mergeEvalJson(results[k]!.correctedRaw ?? '', v),
                passes: 1,
                reason: 'batch director correction',
              );
            }
          }
        }
      }
    } catch (_) {
      // fallback: keep the initial rule corrections
    }

    onVerificationPhase?.call(false);
    return results;
  }
}

class VerificationResult {
  final String status;
  final int passes;
  final String? correctedRaw;
  final String reason;

  VerificationResult({
    required this.status,
    required this.passes,
    this.correctedRaw,
    this.reason = '',
  });

  factory VerificationResult.accepted({
    required String raw,
    required int passes,
    String reason = '',
  }) => VerificationResult(
    status: 'accepted',
    passes: passes,
    correctedRaw: raw,
    reason: reason,
  );

  factory VerificationResult.corrected({
    required String raw,
    required int passes,
    String reason = '',
  }) => VerificationResult(
    status: 'corrected',
    passes: passes,
    correctedRaw: raw,
    reason: reason,
  );

  Map<String, dynamic> toMetadata() => {
    'status': status,
    'passes': passes,
    if (reason.isNotEmpty) 'reason': reason,
  };
}
