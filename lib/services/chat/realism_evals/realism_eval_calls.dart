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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/llm_eval_engine.dart'
    show recentExchange, recentExchangeThroughLastUser;
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_evals/realism_batch_collector.dart';
import 'package:front_porch_ai/services/chat/realism_evals/realism_eval_support.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The 4 multi-call realism eval calls (Cluster D) for [RealismEvals]:
/// relationship, emotional state, physical state, narrative. PUBLIC (not
/// `_private`) because these are invoked from the chat_service library's
/// god thins (`realism_judges.dart`) and from
/// test/services/chat/realism_evals_test.dart — a private extension would
/// not resolve outside this library. Split out of realism_evals.dart
/// verbatim as part of the god-file elimination campaign; see
/// docs/design/god-file-elimination.md.
class RealismEvalCalls {
  final RealismEvals evals;
  final RealismEvalSupport support;
  final RealismBatchCollector batch;

  RealismEvalCalls({
    required this.evals,
    required this.support,
    required this.batch,
  });

  // ── The 5 Realism Eval Calls (full bodies moved here from engine in step 10) ──

  Future<void> evaluateRelationshipCall({
    void Function(String)? onChunk,
  }) async {
    if (!evals.getRealismEnabled()) return;
    if (evals.getActiveCharacter() == null && evals.getActiveGroup() == null) {
      return;
    }
    if (evals.getActiveGroup() != null && evals.getIsObserverMode()) {
      return; // Director excluded
    }

    // 4-message window, unified across the three prefix-sharing judges (was
    // 3 here): the recent block must be built from the same inputs everywhere
    // or the judges' shared context silently diverges per eval. Routed
    // through the ONE window builder (recentExchange — same sender:promptText
    // shape this inline copy had), which also applies the per-message clamp;
    // the inline copies predated it and had already drifted once.
    final recent = recentExchangeThroughLastUser(evals.getMessages(), take: 4);

    if (evals.getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final char = evals.getActiveCharacter()!;
    final charName = char.name;
    final userName = evals.getUserName();

    final dossier = evals.getCharacterDossier(char);
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: evals.relationshipService.shortTermTierName,
      longTermTier: evals.relationshipService.longTermTierName,
      trustTier: evals.relationshipService.trustTierName,
      trustLevel: evals.relationshipService.trustLevel,
      emotion: evals.getCharacterEmotion(),
      emotionIntensity: evals.getEmotionIntensity(),
    );

    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.relationshipEvalPrompt(
          preferences: evals.getPreferences?.call() ?? '',
          ambitions: evals.getAmbitions?.call() ?? const [],
          charName: charName,
          userName: userName,
          dossier: dossier,
          standing: standing,
          recent: recent,
          toolsMode: toolsMode,
        );
    // Text-mode variant for the verifier/batch context (the format the
    // downstream parse — and any Director re-fire — actually expects).
    final prompt = buildPrompt(toolsMode: false);

    var parsed = false;
    try {
      debugPrint('[Realism] Evaluating relationship dynamic...');
      final raw = await support.fireEval(
        toolName: kRelationshipTool,
        tools: kJudgeEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) {
        debugPrint('[Realism:Relationship] Failed — no answer');
        support.markFeelingsUnscored();
        return;
      }

      final searchText = evals.stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      // Verifier (if wired and per-char enabled): receives full latent (prompt + pre + char + *all* injections at fire + scene + kind).
      // Effective text (original or corrected) used for parse/apply/side effects + metadata for chip.
      if (batch.active) {
        batch.pending.add({
          'kind': 'relationship',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {'personality': dossier, 'standing': standing},
        });
        // Defer verify + parse/apply (_parseAndApplyRelationshipDeltas for bond/trust/arousal chips) to the
        // god post-mains batch (getCollected + verifyBatch + applyBatchResults). Direct path does it inline.
        return;
      }

      final effectiveText = await support.verifyAndApply(
        evalKind: 'relationship',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {'personality': dossier, 'standing': standing},
      );

      // Unified parse/apply (also used by one-shot). applyArousal:false — in
      // multi-call mode the emotional eval requests and owns arousal_delta; a
      // model volunteering it here used to get it applied twice in one turn.
      final res = support.parseAndApplyRelationshipDeltas(
        effectiveText,
        applyArousal: false,
      );
      parsed = true;

      debugPrint(
        '[Realism:Relationship] Bond: ${res.bondDelta} (${res.bondReason.isNotEmpty ? res.bondReason : 'no reason'}) | Trust: ${res.trustDelta} (${res.trustReason.isNotEmpty ? res.trustReason : 'no reason'})',
      );
      debugPrint(
        '[Realism:Metadata] _pendingRealismMetadata after relationship eval: ${evals.getPendingRealismMetadata()}',
      );
    } catch (e) {
      debugPrint('[Realism:Relationship] Failed: $e');
      if (!parsed) support.markFeelingsUnscored();
    }
  }

  Future<void> evaluateEmotionalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!evals.getRealismEnabled()) return;
    if (evals.getActiveCharacter() == null && evals.getActiveGroup() == null) {
      return;
    }
    if (evals.getActiveGroup() != null && evals.getIsObserverMode()) return;
    // Same 4-message window as the other judges, same one builder + clamp.
    final recent = recentExchangeThroughLastUser(evals.getMessages(), take: 4);
    if (evals.getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final char = evals.getActiveCharacter()!;
    final charName = char.name;
    final userName = evals.getUserName();

    final dossier = evals.getCharacterDossier(char);
    // Previous-turn mood rides the standing line so the judge names the new
    // emotion with natural inertia instead of re-deciding from scratch.
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: evals.relationshipService.shortTermTierName,
      longTermTier: evals.relationshipService.longTermTierName,
      trustTier: evals.relationshipService.trustTierName,
      trustLevel: evals.relationshipService.trustLevel,
      emotion: evals.getCharacterEmotion(),
      emotionIntensity: evals.getEmotionIntensity(),
    );
    final arousalEnabled = evals.nsfwService.nsfwCooldownEnabled;
    final labels = evals.getExpressionEnabled()
        ? EmotionLabels.all
        : const <String>[];

    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.emotionalEvalPrompt(
          preferences: evals.getPreferences?.call() ?? '',
          ambitions: evals.getAmbitions?.call() ?? const [],
          charName: charName,
          userName: userName,
          dossier: dossier,
          standing: standing,
          recent: recent,
          arousalEnabled: arousalEnabled,
          arousalLevel: evals.nsfwService.arousalLevel,
          refractoryMinutesLeft: evals.nsfwService.refractoryMinutesRemaining,
          clockRunning: evals.nsfwService.clockRunning,
          allowedEmotionLabels: labels,
          toolsMode: toolsMode,
        );
    final prompt = buildPrompt(toolsMode: false);

    try {
      debugPrint(
        '[Realism] Evaluating emotional state... '
        '(nsfwArousal=${evals.nsfwService.nsfwCooldownEnabled}, '
        'arousalLevel=${evals.nsfwService.arousalLevel})',
      );
      final raw = await support.fireEval(
        toolName: kEmotionalTool,
        tools: kJudgeEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) return;

      final searchText = evals.stripThinkBlocks(raw);
      var text = searchText.isNotEmpty ? searchText : raw;

      if (batch.active) {
        batch.pending.add({
          'kind': 'emotional_state',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {
            'personality': dossier,
            'standing': standing,
            if (labels.isNotEmpty)
              'emotion_constraint': RealismPromptBuilder.emotionLabelConstraint(
                labels,
              ),
          },
        });
        return;
      }

      final effectiveText = await support.verifyAndApply(
        evalKind: 'emotional_state',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {
          'personality': dossier,
          'standing': standing,
          if (labels.isNotEmpty)
            'emotion_constraint': RealismPromptBuilder.emotionLabelConstraint(
              labels,
            ),
        },
      );
      text = effectiveText; // rebind (var allows)

      // applyArousal:true — this eval's prompt requests arousal_delta, so it
      // is the multi-call owner of the field.
      await support.applyEmotionalResults(text, applyArousal: true);
      debugPrint(
        '[Realism:Emotion] Emotion: ${evals.getCharacterEmotion()} (${evals.getEmotionIntensity()})',
      );
    } catch (e) {
      debugPrint('[Realism:Emotion] Failed: $e');
    }
  }

  /// Scene time, and — in [postureOnly] mode — the post-generation posture
  /// pass.
  ///
  /// [timeOnly] drops speaker scoring when the engine is off — there is
  /// no speaker to score. [postureOnly] is the other end: no clock at all,
  /// just "where did this reply leave them", fired AFTER generation from
  /// chat_service_generation_postgen.dart. Both stay THIS method rather than
  /// becoming siblings, because the part that must not drift is everything
  /// around the call — the six-message window, the character resolution, and
  /// the argument list handed to TimeService are literally shared, so the
  /// posture pass can never end up reading a different scene than the clock.
  ///
  /// The window is why the mode change works at all: post-generation the
  /// reply is already `_messages.last`, so these same six messages carry the
  /// text the character just wrote. Pre-generation they could not.
  Future<void> evaluatePhysicalStateCall({
    void Function(String)? onChunk,
    bool timeOnly = false,
    bool postureOnly = false,
    bool skipClockAdvance = false,
    bool skipTodayEval = false,
  }) async {
    if (!timeOnly) {
      if (!evals.getRealismEnabled()) return;
      if (evals.getActiveCharacter() == null &&
          evals.getActiveGroup() == null) {
        return;
      }
      if (evals.getActiveGroup() != null && evals.getIsObserverMode()) return;
    }

    // 6-message window through the one builder + clamp. A clamped middle
    // can in principle hide a mid-novella "goodnight" from the new_day
    // corroboration scan, but sleep language lives at message edges in
    // practice — and the same clamp applies to the one-shot window, so the
    // two clock paths stay in lockstep.
    final recent = recentExchange(evals.getMessages(), take: 6);
    // Under the engine this path needs a character (the group per-speaker dance
    // impersonates one first). timeOnly does not: its prompt names nobody,
    // which is also why it works unchanged in a group, where time is
    // chat-scoped rather than per-speaker.
    if (!timeOnly && evals.getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet.
      // (Time advance is chat-scoped and handled via delegation when active char is impersonated for group speaker.)
      return;
    }
    final charName = evals.getActiveCharacter()?.name ?? '';

    // Both the clock advance and the posture pass are TimeService's; this
    // method only assembles the scene they read. shortTermTierName resolves
    // via relationshipService.
    await evals.timeService.evaluateTimeProgressAndPostureIfNeeded(
      charName: charName,
      recent: recent,
      shortTermTierName: evals.relationshipService.shortTermTierName,
      onChunk: onChunk,
      fireLLMEval: evals.fireLLMEval,
      stripThinkBlocks: evals.stripThinkBlocks,
      extractJsonBool: evals.extractJsonBool,
      setSpatialStance: evals.relationshipService.setSpatialStance,
      getCurrentSpatialStance: () => evals.relationshipService.spatialStance,
      getCharacterEmotion: evals.getCharacterEmotion,
      getEmotionIntensity: evals.getEmotionIntensity,
      timeOnly: timeOnly,
      postureOnly: postureOnly,
      skipClockAdvance: skipClockAdvance,
      skipTodayEval: skipTodayEval,
    );
  }

  Future<void> evaluateNarrativeCall({void Function(String)? onChunk}) async {
    if (!evals.getRealismEnabled()) return;
    if (evals.getActiveCharacter() == null && evals.getActiveGroup() == null) {
      return;
    }
    if (evals.getActiveGroup() != null && evals.getIsObserverMode()) return;
    // Same 4-message window as the other judges, same one builder + clamp.
    final recent = recentExchangeThroughLastUser(evals.getMessages(), take: 4);
    if (evals.getActiveCharacter() == null) {
      // This path requires an active character (the group per-speaker path
      // temporarily sets _activeCharacter before calling us for parity).
      return;
    }
    final char = evals.getActiveCharacter()!;
    final charName = char.name;
    final userName = evals.getUserName();
    final primary = evals.getPrimaryObjective();

    final dossier = evals.getCharacterDossier(char);
    // Same standing/preferences the other two judges build from the same
    // sources — the shared prefix is byte-identical only because every judge
    // is handed the same inputs (see RealismPromptBuilder.judgePrefix).
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: evals.relationshipService.shortTermTierName,
      longTermTier: evals.relationshipService.longTermTierName,
      trustTier: evals.relationshipService.trustTierName,
      trustLevel: evals.relationshipService.trustLevel,
      emotion: evals.getCharacterEmotion(),
      emotionIntensity: evals.getEmotionIntensity(),
    );
    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.narrativeEvalPrompt(
          charName: charName,
          userName: userName,
          dossier: dossier,
          standing: standing,
          preferences: evals.getPreferences?.call() ?? '',
          recent: recent,
          primaryObjective: primary?.objective,
          ambitions: evals.getAmbitions?.call() ?? const [],
          toolsMode: toolsMode,
        );
    final prompt = buildPrompt(toolsMode: false);

    try {
      final raw = await support.fireEval(
        toolName: kNarrativeTool,
        tools: kJudgeEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) return;
      var text = evals.stripThinkBlocks(raw).isNotEmpty
          ? evals.stripThinkBlocks(raw)
          : raw;
      if (batch.active) {
        batch.pending.add({
          'kind': 'narrative',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {'personality': dossier},
        });
        return;
      }

      final effectiveText = await support.verifyAndApply(
        evalKind: 'narrative',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {'personality': dossier},
      );
      text = effectiveText; // rebind for downstream (no other code change)

      await support.applyNarrativeResults(text);
    } catch (e) {
      debugPrint('[Realism:Narrative] Failed: $e');
    }
  }
}
