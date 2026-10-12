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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';

/// Shared appliers/parsers (Cluster B) + fire/verify plumbing (Cluster C) for
/// [RealismEvals]. Private — only ever called from within this library (the
/// shell's Cluster A batch API + the public call extensions in
/// realism_evals.calls.dart / realism_evals.one_shot.dart). Split out of
/// realism_evals.dart verbatim as part of the god-file elimination campaign;
/// see docs/design/god-file-elimination.md.
class RealismEvalSupport {
  final RealismEvals evals;

  RealismEvalSupport(this.evals);

  /// Apply emotional scalar + arousal pending updates from a (possibly corrected) eval text.
  /// Mirrors the direct-path logic after _verify in evaluateEmotionalStateCall so batch and
  /// direct produce identical emotion/arousal side effects and chip metadata.
  ///
  /// [applyArousal] names this call's arousal ownership explicitly (see
  /// [_parseAndApplyRelationshipDeltas] for the ownership rule). True on both
  /// live paths — the emotional eval is the multi-call owner; false only in
  /// the future-proof batch-oneShot arm, where the relationship parse of the
  /// same fused text already applied it.
  Future<void> applyEmotionalResults(
    String text, {
    required bool applyArousal,
  }) async {
    if (evals.isEvalCancelled()) return;
    final emotionMatch = RegExp(r'"emotion"\s*:\s*"([^"]+)"').firstMatch(text);
    if (emotionMatch != null) {
      evals.setCharacterEmotion(emotionMatch.group(1)!.toLowerCase().trim());
    }

    final intensityMatch = RegExp(
      r'"emotion_intensity"\s*:\s*"([^"]+)"',
    ).firstMatch(text);
    if (intensityMatch != null) {
      evals.setEmotionIntensity(intensityMatch.group(1)!.toLowerCase().trim());
    }

    if (applyArousal && evals.nsfwService.nsfwCooldownEnabled) {
      final arDelta = evals.extractJsonInt(text, 'arousal_delta');
      if (arDelta != null) {
        // Record the EFFECTIVE delta (post-clamp + refractory physiology) so
        // chips show what actually happened and regen revert stays exact.
        final arousalDelta = evals.nsfwService.applyEvalArousalDelta(
          arDelta.clamp(kMinArousalDelta, kMaxArousalDelta),
        );
        if (arousalDelta != 0) {
          var pending = evals.getPendingRealismMetadata() ?? {};
          pending['arousal_delta'] = arousalDelta;
          evals.setPendingRealismMetadata(pending);
        }
      }
    }
  }

  /// Apply fixation update + autonomous objective proposal (if any) from a (possibly director-corrected)
  /// narrative eval text. Extracted here so the batch apply path can reuse the exact same
  /// side-effect logic (and dedup) without growing god or duplicating the json+regex fallbacks.
  Future<void> applyNarrativeResults(String text) async {
    if (evals.isEvalCancelled()) return;
    // Robust extraction (survives Director reprocess/correction which may reformat/partial JSON).
    // Inline (no new named helper/method per rules for god; private here in leaf is fine).
    // Parse JSON once (both keys live in the same payload) rather than twice.
    String fixationRaw = '';
    String objectiveRaw = '';
    String servesRaw = '';
    try {
      final noFence = text
          .replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ')
          .trim();
      final si = noFence.indexOf('{');
      final ei = noFence.lastIndexOf('}');
      if (si >= 0 && ei > si) {
        final obj = jsonDecode(noFence.substring(si, ei + 1));
        if (obj is Map) {
          if (obj['fixation_topic'] != null) {
            fixationRaw = obj['fixation_topic'].toString().trim();
          }
          if (obj['proposed_objective'] != null) {
            objectiveRaw = obj['proposed_objective'].toString().trim();
          }
          if (obj['serves_ambition'] != null) {
            servesRaw = obj['serves_ambition'].toString().trim();
          }
        }
      }
    } catch (_) {}
    if (fixationRaw.isEmpty) {
      fixationRaw = evalJsonString(text, 'fixation_topic')?.trim() ?? '';
    }
    evals.relationshipService.updateFixationFromEvalResult(
      fixationRaw.isNotEmpty ? fixationRaw : '',
    );

    if (objectiveRaw.isEmpty) {
      objectiveRaw = evalJsonString(text, 'proposed_objective')?.trim() ?? '';
    }
    if (servesRaw.isEmpty) {
      // Same regex floor the other two fields get. Unquoted is allowed here
      // because a model asked for "the NUMBER" often answers with a bare 2.
      final m3 = RegExp(
        '"serves_ambition"\\s*:\\s*"?([^",}]*)"?',
        dotAll: true,
      ).firstMatch(text);
      servesRaw = m3?.group(1)?.trim() ?? '';
    }
    // Objectives off ⇒ the character does not get to start new quests. The
    // eval already ran (it carries fixation too), so this costs nothing extra;
    // it just declines to act on the proposal half of the answer.
    final objectivesOn = evals.getObjectivesEnabled?.call() ?? true;
    if (objectivesOn &&
        objectiveRaw.toLowerCase() != 'none' &&
        objectiveRaw.isNotEmpty) {
      final active = evals.getActiveObjectives();
      final isDuplicate = active.any(
        (o) => o.objective.toLowerCase() == objectiveRaw.toLowerCase(),
      );
      if (!isDuplicate &&
          !TodayLineTag.proposedCollidesWithToday(objectiveRaw, text)) {
        // Claim the main-quest slot when it's free: the character's self-initiated
        // goal becomes their driving primary quest with a full task arc. When a
        // primary already exists (user-set or an earlier autonomous quest), the
        // proposal stays a side quest — never displace an existing main quest.
        final becomesPrimary = evals.getPrimaryObjective() == null;
        debugPrint(
          '[Realism:Narrative] Autonomous objective proposed: $objectiveRaw '
          '(${becomesPrimary ? "primary — main-quest slot free" : "secondary — primary exists"})',
        );
        // Pass autoGenerateTasks:true so the character's self-initiated goal gets
        // concrete subtasks (making autonomous objectives feel like real pursuits
        // with steps the character can accomplish).
        // (thin delegation to god setObjective per plan for step9; full proposal logic here)
        await evals.setObjective(
          objectiveRaw,
          isPrimary: becomesPrimary,
          autoGenerateTasks: true,
          // Resolved against the SAME roster the prompt numbered, so "2" here
          // and "2" there are the same ambition. Null when the model said
          // none, answered junk, or was never asked (no ambitions).
          servedAmbition: RealismPromptBuilder.resolveServedAmbition(
            servesRaw,
            evals.getAmbitions?.call() ?? const [],
          ),
        );
      }
    }
  }

  /// Pre-parse fire for the JSON evals — thin over the ONE shared
  /// negotiation ([fireStructuredEval] in pass_support.dart): tools first
  /// when the backend allows (canonical JSON synthesized from the call via
  /// realism_tools), text-reply salvage, streaming text fallback otherwise.
  Future<String?> fireEval({
    required String toolName,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
    void Function(String)? onChunk,
  }) => fireStructuredEval(
    probe: evals.probe,
    backendIdentity: evals.getBackendIdentity(),
    debugLabel: toolName,
    tools: tools,
    buildPrompt: buildPrompt,
    callToText: (resp) => realismToolCallToJson(toolName, resp.calls),
    fireToolEval: evals.fireToolEval,
    fireTextEval: evals.fireLLMEval,
    isCancelled: evals.isEvalCancelled,
    onChunk: onChunk,
    toolChoice: toolName,
    getPreferTextEvals: evals.getPreferTextEvals,
  );

  /// Shared post-fire verifier wrapper (used by all 5 realism paths + oneShot).
  /// Assembles the rich latent bundle from what this leaf just used (prompt, pre via capture cb,
  /// active char, messages, scene from recent or passed response context) and calls the verify cb if present.
  /// Returns the (possibly corrected) text for downstream parse/apply, and attaches verification
  /// metadata to pending for the message bubble chip.
  /// 1:1/group dispatch and pre state are handled by the cbs (god impersonation dance ensures correct card + pre-decay snapshot).
  Future<String> verifyAndApply({
    required String evalKind,
    required String textAfterStrip,
    required String promptUsed,
    required String sceneForContext,
    Map<String, String>? injections,
  }) async {
    if (evals.verifyRealismOutput == null) return textAfterStrip;

    // Fast-path when the per-character "Director / Verifier" (realismVerificationEnabled) is off
    // (the default). This skips expensive work that was previously done for every one of the
    // 5 pre-response realism evals (and the post-gen needs impact): captureRealismState() (full
    // scalar + needs vector + time snapshot), getMessages() list, frontPorchExtensions.toJson(),
    // building the rich latent bundle, etc. The inner verifier also early-returns when disabled,
    // but we avoid the call-site cost entirely. On remote APIs (e.g. nano-gpt) this keeps the
    // "Realism Engine processing" phase for the 5 evals at the original speed. When the flag is
    // on for a character (opt-in for higher-fidelity reviewed deltas), the full verification
    // (rule checks + possible LLM critique + re-fire up to max reprocesses) still runs.
    final char = evals.getActiveCharacter();
    final verifOn =
        (char?.frontPorchExtensions?.realismVerificationEnabled ?? false) &&
        evals.getRealismEnabled() &&
        (evals.getActiveGroup() == null || !evals.getIsObserverMode());
    if (!verifOn) return textAfterStrip;

    try {
      final vres = await evals.verifyRealismOutput!(
        evalKind: evalKind,
        rawOutput: textAfterStrip,
        sceneResponse: sceneForContext,
        preState: evals.captureRealismState(),
        activeChar: evals.getActiveCharacter(),
        activeGroup: evals.getActiveGroup(),
        recentMessages: evals.getMessages(),
        promptText: promptUsed,
        injections: injections ?? const <String, String>{},
        strictnessOverride: null, // leaf uses live cb inside verifier
        maxPassesOverride: null,
      );
      if (vres.status.isNotEmpty) {
        // Attach for bubble chip (and any sidebar notes). God will also stamp on the final ChatMessage.
        final current =
            (evals.getPendingRealismMetadata() ?? <String, dynamic>{});
        current[RealismVerification.kMetaKey] = vres.toMetadata();
        evals.setPendingRealismMetadata(current);
        debugPrint(
          '[Realism:Verifier] Attached to pending for kind=$evalKind status=${vres.status} passes=${vres.passes}',
        );
      }
      return vres.correctedRaw ?? textAfterStrip;
    } catch (e) {
      debugPrint('[Realism:Verifier] Wrapper error (passthrough): $e');
      return textAfterStrip;
    }
  }

  /// The bond/trust judge ran and gave nothing readable. Drops any bond/trust
  /// keys already pending (a greeting baseline's, say) so this reply cannot
  /// show someone else's score, and stamps [kFeelingsUnscoredMeta]. A
  /// cancelled turn is thrown away, so it is left alone.
  void markFeelingsUnscored() {
    if (evals.isEvalCancelled()) return;
    final pending = evals.getPendingRealismMetadata() ?? {};
    for (final key in const [
      'bond_delta',
      'trust_delta',
      'bond_reason',
      'trust_reason',
    ]) {
      pending.remove(key);
    }
    pending[kFeelingsUnscoredMeta] = true;
    evals.setPendingRealismMetadata(pending);
  }

  /// Parses relationship/trust (+ arousal when this call owns it) fields from
  /// an eval JSON text, applies the side effects (score/trust deltas to services,
  /// arousal to nsfwService), populates pending metadata for chips/reasons using
  /// only nonzero deltas (reasons are populated when present even if deltas are 0),
  /// and returns the resolved values for caller debug logging.
  ///
  /// This single implementation is used by both the separate relationship eval
  /// (multi-call) and the fused one-shot eval, guaranteeing identical clamp
  /// behavior and pending population for bond/trust/arousal.
  ///
  /// ONE AROUSAL OWNER PER TURN (eval review item 7, 2026-08-10): the eval
  /// whose prompt REQUESTS arousal_delta is the only one allowed to apply it.
  /// In multi-call mode that is the emotional-state eval, so the relationship
  /// path passes [applyArousal]=false; in one-shot mode the fused call is the
  /// requester, so it passes true. The old behavior parsed arousal here
  /// "best-effort" even on the relationship path — a chatty model that
  /// volunteered the field got it applied TWICE in one turn (once here, once
  /// by the emotional eval), with the chip showing only the second value.
  ({
    int bondDelta,
    int trustDelta,
    int arousalDelta,
    String bondReason,
    String trustReason,
  })
  parseAndApplyRelationshipDeltas(String text, {required bool applyArousal}) {
    if (evals.isEvalCancelled()) {
      return (
        bondDelta: 0,
        trustDelta: 0,
        arousalDelta: 0,
        bondReason: '',
        trustReason: '',
      );
    }
    // Bond / relationship delta (per prompt range)
    final relDelta = evals.extractJsonInt(text, 'relationship_delta');
    int bondDelta = 0;
    if (relDelta != null) {
      bondDelta = relDelta.clamp(kMinRelationshipDelta, kMaxRelationshipDelta);
      evals.relationshipService.applyScoreDelta(bondDelta);
    }

    // Trust delta (user behavior only; per prompt range)
    int trustDelta = 0;
    final trDelta = evals.extractJsonInt(text, 'trust_delta');
    if (trDelta != null) {
      trustDelta = trDelta.clamp(kMinTrustDelta, kMaxTrustDelta);
      if (trustDelta != 0) {
        evals.relationshipService.applyTrustDelta(trustDelta);
      }
    }

    // Arousal (only when NSFW cooldowns are enabled AND this call owns the
    // field — see the ownership rule in the doc comment). arousalDelta ends up
    // holding the EFFECTIVE delta (post-clamp + refractory physiology) so
    // pending metadata, chips, and regen revert all agree on what landed.
    int arousalDelta = 0;
    if (applyArousal && evals.nsfwService.nsfwCooldownEnabled) {
      final arDelta = evals.extractJsonInt(text, 'arousal_delta');
      if (arDelta != null) {
        arousalDelta = evals.nsfwService.applyEvalArousalDelta(
          arDelta.clamp(kMinArousalDelta, kMaxArousalDelta),
        );
      }
    }

    // Neither field in the answer (prose, a refusal) means nothing was
    // scored. Writing 0/0 here drew "Bond unchanged" for that turn.
    if (relDelta == null && trDelta == null) {
      markFeelingsUnscored();
      if (arousalDelta != 0) {
        final pending = evals.getPendingRealismMetadata() ?? {};
        pending['arousal_delta'] = arousalDelta;
        evals.setPendingRealismMetadata(pending);
      }
      return (
        bondDelta: 0,
        trustDelta: 0,
        arousalDelta: arousalDelta,
        bondReason: '',
        trustReason: '',
      );
    }

    // Always keep both deltas, including 0. A missing chip reads as "the
    // judge never ran." Revert still ignores a 0. Arousal stays nonzero-only.
    var pending = evals.getPendingRealismMetadata() ?? {};
    pending.remove(kFeelingsUnscoredMeta);
    pending['bond_delta'] = bondDelta;
    pending['trust_delta'] = trustDelta;
    if (arousalDelta != 0) pending['arousal_delta'] = arousalDelta;
    evals.setPendingRealismMetadata(pending);

    // Reasons (for hover tooltips on chips). Always extract; set if present
    // and not the sentinel "none".
    final rawBondReason = evalJsonString(text, 'bond_reason')?.trim() ?? '';
    final bondReason = rawBondReason.toLowerCase() == 'none'
        ? ''
        : rawBondReason;
    if (bondReason.isNotEmpty) {
      var pending = evals.getPendingRealismMetadata() ?? {};
      pending['bond_reason'] = bondReason;
      evals.setPendingRealismMetadata(pending);
    }

    final rawTrustReason = evalJsonString(text, 'trust_reason')?.trim() ?? '';
    final trustReason = rawTrustReason.toLowerCase() == 'none'
        ? ''
        : rawTrustReason;
    if (trustReason.isNotEmpty) {
      var pending = evals.getPendingRealismMetadata() ?? {};
      pending['trust_reason'] = trustReason;
      evals.setPendingRealismMetadata(pending);
    }

    return (
      bondDelta: bondDelta,
      trustDelta: trustDelta,
      arousalDelta: arousalDelta,
      bondReason: bondReason,
      trustReason: trustReason,
    );
  }
}
