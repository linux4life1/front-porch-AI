// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart'
    show
        kMinRelationshipDelta,
        kMaxRelationshipDelta,
        kMinTrustDelta,
        kMaxTrustDelta,
        kMinArousalDelta,
        kMaxArousalDelta;

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

      final reRule = _applyRuleChecks(reOut, bundle, strict);
      currentRaw = reRule.correctedRaw ?? reOut;
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
    List<({
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
    })> items,
  ) async {
    if (items.isEmpty) return {};

    final enabled = getRealismVerificationEnabled();
    if (!enabled) {
      return {
        for (final i in items)
          i.evalKind: VerificationResult.accepted(raw: i.rawOutput, passes: 0)
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
        'char_personality': (it.activeChar ?? getActiveCharacter())?.personality ?? '',
        'char_scenario': (it.activeChar ?? getActiveCharacter())?.scenario ?? '',
        'char_frontPorch': (it.activeChar ?? getActiveCharacter())?.frontPorchExtensions?.toJson() ?? {},
        'group': {'name': (it.activeGroup ?? getActiveGroup())?.name ?? ''},
        'recent': (it.recentMessages ?? getMessages()).length,
        'strictness': it.strictnessOverride ?? getVerificationStrictness(),
        'max_passes': it.maxPassesOverride ?? getVerificationMaxReprocesses(),
        'user': getUserName(),
      };

      final rule = _applyRuleChecks(it.rawOutput, bundle, it.strictnessOverride ?? getVerificationStrictness());
      if (rule.passed) {
        results[it.evalKind] = VerificationResult.accepted(raw: it.rawOutput, passes: 0);
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

    onVerificationPhase?.call(true, pass: 1, max: getVerificationMaxReprocesses());

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
      final noFence = reOut.replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ').trim();
      final si = noFence.indexOf('{');
      final ei = noFence.lastIndexOf('}');
      if (si >= 0 && ei > si) {
        final obj = jsonDecode(noFence.substring(si, ei + 1));
        if (obj is Map) {
          for (final entry in obj.entries) {
            final k = entry.key.toString();
            final v = entry.value?.toString() ?? '';
            if (results.containsKey(k) && v.isNotEmpty) {
              results[k] = VerificationResult.corrected(
                raw: v,
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

  String _buildBatchCritiquePrompt({
    required List<({
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
    })> items,
    required Map<String, VerificationResult> initialCorrections,
  }) {
    final buf = StringBuffer();
    buf.writeln('You are the Realism Director reviewing a batch of realism eval outputs for consistency.');
    buf.writeln('For each eval kind below, the "raw" is the model\'s structured output for that eval.');
    buf.writeln('Apply the same rules as single verification (scene-faithful deltas, no contradictions with narrative/pre-state, inertia, etc.).');
    buf.writeln('Return ONLY a flat JSON object with keys = the evalKind and values = the corrected raw string for that kind (or the original if no change needed).');
    buf.writeln('Example: {"relationship": "{...corrected...}", "emotional_state": "{...}"}');
    buf.writeln();

    for (final it in items) {
      buf.writeln('--- EVAL: ${it.evalKind} ---');
      buf.writeln('PROMPT USED:\n${it.promptText ?? ""}\n');
      buf.writeln('SCENE / RECENT:\n${it.sceneResponse}\n');
      buf.writeln('RAW OUTPUT:\n${it.rawOutput}\n');
      if (initialCorrections[it.evalKind] != null) {
        buf.writeln('INITIAL RULE-BASED CORRECTION (if any):\n${initialCorrections[it.evalKind]!.correctedRaw ?? it.rawOutput}\n');
      }
      buf.writeln('--- END ${it.evalKind} ---\n');
    }

    buf.writeln('Respond with ONLY the JSON object of corrections.');
    return buf.toString();
  }

  _RuleResult _applyRuleChecks(
    String raw,
    Map<String, dynamic> bundle,
    int strict,
  ) {
    final kind = bundle['eval_kind'] as String? ?? '';
    final scene = (bundle['scene'] as String? ?? '').toLowerCase();
    final strictFactor = (strict / 3.0).clamp(0.6, 1.4);
    final pre = (bundle['pre_state'] as Map?) ?? {};
    final preBond =
        (pre['short_term_bond'] as num?)?.toInt() ??
        (pre['bond'] as num?)?.toInt() ??
        0;

    // deltas range
    for (final entry in {
      'relationship_delta': (kMinRelationshipDelta, kMaxRelationshipDelta),
      'trust_delta': (kMinTrustDelta, kMaxTrustDelta),
      'arousal_delta': (kMinArousalDelta, kMaxArousalDelta),
    }.entries) {
      final d = extractJsonInt(raw, entry.key);
      if (d != null) {
        final (lo, hi) = entry.value;
        final c = d.clamp(lo, hi);
        if (c != d) {
          return _RuleResult(
            false,
            '${entry.key} out of range',
            _correctedJson(raw, entry.key, c),
          );
        }
      }
    }

    if (kind == 'relationship' || kind == 'oneShot') {
      final delta = extractJsonInt(raw, 'relationship_delta') ?? 0;
      // Sign-agnostic support check. The DIRECTION of a reaction is the
      // judge's subjective, personality-informed call — unwanted affection can
      // legitimately score negative for a guarded/dominant character — so this
      // rule only asks whether the scene carries enough emotional charge to
      // justify a large MAGNITUDE at all. It must never demand that valence
      // match affection-vs-violence keywords (the old hasPos/hasNeg split
      // shrank correct negative reactions to smothering scenes).
      final charged =
          const [
            'kiss', 'hug', 'love', 'affection', 'tender', 'embrace', 'gift',
            'confess', 'tears', 'cry', 'blush', 'whisper', 'tremb', 'grip',
            'slap', 'push', 'hate', 'angry', 'yell', 'shove', 'cold',
            'betray', 'insult', 'mock', 'ignore', 'reject', 'threat',
            'apolog', 'protect', 'sacrific', 'promise',
          ].any(scene.contains) ||
          (scene.contains('smile') && scene.contains('you'));
      final absD = delta.abs();
      if (absD > (10 * strictFactor) && !charged) {
        return _RuleResult(
          false,
          'large bond delta w/o emotionally charged scene',
          _correctedJson(
            raw,
            'relationship_delta',
            (delta * 0.3).round().clamp(
              -kMaxRelationshipDelta,
              kMaxRelationshipDelta,
            ),
          ),
        );
      }
      if (preBond.abs() > 200 && absD > 12 && strict >= 3) {
        return _RuleResult(
          false,
          'extreme bond swing',
          _correctedJson(
            raw,
            'relationship_delta',
            (delta * 0.4).round().clamp(
              kMinRelationshipDelta,
              kMaxRelationshipDelta,
            ),
          ),
        );
      }
    }

    if (kind == 'narrative' || kind == 'oneShot' || kind == 'relationship') {
      final fix = (_extractJsonString(raw, 'fixation_topic') ?? '')
          .toLowerCase()
          .trim();
      if (fix.isNotEmpty &&
          fix != 'none' &&
          ![
            'can\'t stop',
            'obsess',
            'fixated',
            'intrusive',
            'mind keeps',
          ].any(scene.contains) &&
          strict >= 3) {
        return _RuleResult(
          false,
          'fixation w/o obsessive',
          raw.replaceAll(
            RegExp('"fixation_topic"\\s*:\\s*"[^"]*"'),
            '"fixation_topic": "none"',
          ),
        );
      }
    }

    if (kind == 'emotional_state' || kind == 'oneShot') {
      final em = (_extractJsonString(raw, 'character_emotion') ?? '')
          .toLowerCase();
      final inten = extractJsonInt(raw, 'emotion_intensity') ?? 1;
      if (em.isNotEmpty &&
          !_sceneSupportsEmotion(scene, em) &&
          inten >= 2 &&
          strict >= 3) {
        return _RuleResult(
          false,
          'strong emotion w/o support',
          _correctedJson(raw, 'emotion_intensity', 1),
        );
      }
    }

    if (kind == 'physical_state' || kind == 'narrative' || kind == 'oneShot') {
      final st = (_extractJsonString(raw, 'spatial_stance') ?? '')
          .toLowerCase();
      if (st.isNotEmpty) {
        final stand = scene.contains('stand') || scene.contains('standing');
        final sit = scene.contains('sit') || scene.contains('sitting');
        final lie =
            scene.contains('lie') ||
            scene.contains('lying') ||
            scene.contains('bed');
        if ((st.contains('stand') && (sit || lie)) ||
            (st.contains('sit') && stand) ||
            (st.contains('lie') && stand)) {
          return _RuleResult(
            false,
            'stance contradict',
            raw.replaceAll(RegExp('"$st"'), '"close / facing you"'),
          );
        }
      }
    }

    final h = extractJsonInt(raw, 'hunger') ?? 0;
    if (h.abs() > (8 * strictFactor) &&
        !scene.contains('eat') &&
        !scene.contains('food')) {
      final v = h.sign * 2;
      final corrected = raw
          .replaceAll(RegExp('"hunger"\\s*:\\s*(-?\\d+)'), '"hunger": $v')
          .replaceAll(RegExp('"hunger"\\s*:\\s*(-?\\d+)'), '"hunger": $v');
      return _RuleResult(false, 'hunger delta w/o eat', corrected);
    }

    return _RuleResult(true, '', null);
  }

  String _buildReprocessCritiquePrompt({
    required String originalRaw,
    required String reason,
    required String suggested,
    required Map<String, dynamic> bundle,
    required int strict,
  }) {
    final tone = strict >= 4
        ? 'Strict director: reject unsupported by latent/pre/scene/char. Minimal corrections.'
        : strict <= 2
        ? 'Lenient director: correct only clear impossibilities. Accept if plausible.'
        : 'Balanced director: correct errors/out-of-range in clamps using context.';
    final charName = bundle['char_name'] as String? ?? 'char';
    final pre = bundle['pre_state'] ?? {};
    final scene = (bundle['scene'] as String? ?? '');
    final kind = bundle['eval_kind'] as String? ?? '';
    final note =
        (kind == 'relationship' ||
            kind == 'emotional_state' ||
            kind == 'physical_state' ||
            kind == 'narrative' ||
            kind == 'oneShot')
        ? 'Classic $kind: prior rejected. Output scene-supported deltas.'
        : '';
    final structHint = (kind == 'narrative')
        ? ' Preserve full shape: include "proposed_objective" ("none" or short goal) and "fixation_topic" (persistent lingering/intrusive thought or "none"). Only correct unsupported values; keep well-supported fixations.'
        : (kind == 'needs_impact')
            ? ' Preserve the needs delta keys (hunger_delta/energy_delta/etc or plain names) + reason + activities. The model is trusted to interpret the full erotic narrative (physical descriptions, self-touch, leaking, charging/aching, dominance, power exchange) and assign reasonable deltas like the other realism evals (bond/emotion etc). Only correct if the numbers clearly contradict what is actually written in the scene or pre-state. Keep scene-faithful numbers.'
            : '';
    final emotionConstraint = (bundle['injections'] as Map<String, dynamic>?)?['emotion_constraint'] as String? ?? '';
    final constraintText = emotionConstraint.isNotEmpty ? '\n$emotionConstraint\n' : '';
    // Persona so the Director corrects subjectively (the eval's dossier when
    // available, else the raw card field). Without this it judged blind and
    // pushed deltas back toward generic-nice.
    final injPersona =
        ((bundle['injections'] as Map<String, dynamic>?)?['personality']
                as String? ??
            '')
            .trim();
    final personaRaw = injPersona.isNotEmpty
        ? injPersona
        : (bundle['char_personality'] as String? ?? '').trim();
    final persona = personaRaw.length > 400
        ? '${personaRaw.substring(0, 400)}…'
        : personaRaw;
    final personaLine = persona.isEmpty
        ? ''
        : '\nPersona (deltas are subjective to this — affection can legitimately score negative for a guarded or dominant character): $persona';
    final s = scene.length > 600 ? scene.substring(0, 600) + '…' : scene;
    return '$tone\n$note$structHint$constraintText$personaLine\n\nEval: $kind for $charName.\nPre: $pre\nScene: $s\n\nOrig: $originalRaw\nReason: $reason\nSuggested: $suggested\n\nRe-eval; ONLY corrected JSON. Deltas to clamps. Match scene and persona if classic.';
  }

  String _correctedJson(String o, String k, int v) {
    final re = RegExp('("$k"\\s*:\\s*)(-?\\d+)', dotAll: true);
    return o.replaceAllMapped(re, (m) => '${m[1]}$v');
  }

  String? _extractJsonString(String r, String k) {
    final m = RegExp('"$k"\\s*:\\s*"([^"]*)"', dotAll: true).firstMatch(r);
    if (m != null) return m.group(1)?.trim();
    final m2 = RegExp('"$k"\\s*:\\s*([^,}\\]]+)', dotAll: true).firstMatch(r);
    return m2?.group(1)?.trim().replaceAll('"', '');
  }

  // DRY emotion support (data map + any match) trims ~30 LOC vs expanded ifs.
  static const Map<String, List<String>> _emotionKeywords = {
    'happy': ['smile', 'laugh', 'giggle', 'happy', 'content', 'joy', 'pleased'],
    'sad': ['tear', 'cry', 'sad', 'quiet', 'sigh', 'melanchol', 'down'],
    'angry': [
      'angry',
      'yell',
      'glare',
      'snap',
      'frustrat',
      'furious',
      'irritat',
    ],
    'arous': [
      'kiss',
      'touch',
      'moan',
      'breath',
      'close',
      'arous',
      'lust',
      'desire',
    ],
    'curious': ['ask', 'lean', 'watch', 'question', 'curious', 'interest'],
  };

  bool _sceneSupportsEmotion(String sceneLower, String emotion) {
    if (emotion.isEmpty) return true;
    for (final entry in _emotionKeywords.entries) {
      if (emotion.contains(entry.key)) {
        return entry.value.any(sceneLower.contains);
      }
    }
    return true;
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

class _RuleResult {
  final bool passed;
  final String reason;
  final String? correctedRaw;
  _RuleResult(this.passed, this.reason, this.correctedRaw);
}
