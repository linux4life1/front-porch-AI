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

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolResponse;
import 'package:front_porch_ai/utils/emotion_labels.dart';

// The per-eval delta limit constants (kMin/kMaxRelationshipDelta etc.) live in
// realism_prompt_builder.dart next to the prompt text that interpolates them.
// Re-exported here so existing importers (realism_verification.dart, tests)
// keep resolving them from this library.
export 'package:front_porch_ai/services/chat/realism_prompt_builder.dart'
    show
        kMinRelationshipDelta,
        kMaxRelationshipDelta,
        kMinTrustDelta,
        kMaxTrustDelta,
        kMinArousalDelta,
        kMaxArousalDelta;

/// Plain (non-ChangeNotifier) leaf sibling to LlmEvalEngine owning the 5
/// realism evaluation calls (relationship, emotional state, physical state,
/// narrative, one-shot) + their prompt builders, orchestration, parse for
/// realism results (bond/trust deltas ± , emotion/inertia, arousal, fixation,
/// spatial stance, time, pending metadata for chips/reasons), and side effects
/// (apply on rel/nsfw, set scalars, updateFixation, setObjective thin cb for
/// autonomous, snapshot for oneShot).
///
/// Per extraction order table in docs/refactoring-guide.md (order 10 after
/// 9/9b llm_eval + needs_impact; depends on llm_eval_engine for fire/strip/extract
/// cbs; prompt builders for the 5 evals full in leaf or coordinated per precedent).
///
/// Extracted as step 10 of Stage 3 god-file modularization.
/// "the 5 realism evaluation calls: relationship, emotional state, physical state,
/// narrative, one-shot" as plain leaf sibling to llm_eval_engine.
///
/// ChatService owns via late final (after _llmEvalEngine) + thins/delegations at
/// *every* prior call site for the 5 _evaluate*Call (full excision of moved code
/// from engine + old thin bodies). Some coordination (setObjective thin for auto
/// proposal in narr/oneShot, physical posture delegate to timeService which
/// receives fire cbs) may stay thin/coordinated in god per precedent (qualify).
///
/// Ctor receives state via granular callbacks (modeled on steps 6-9b + needs_impact:
/// fireLLMEval/strip/extract* (via god thins over engine),
/// getActiveCharacter/getActiveGroup/getIsObserverMode (for guards + 1:1 vs group
/// dispatch via god's impersonation), getUserName, getRealismEnabled, getMessages,
/// get/setPendingRealismMetadata, captureRealismState, get/setCharacterEmotion,
/// get/setEmotionIntensity, relationshipService, nsfwService, timeService (for
/// physical + ctx in oneShot), getExpressionEnabled (for prompt label list),
/// getPrimaryObjective/getActiveObjectives/setObjective (for narr/oneShot proposed
/// objective under impersonation), getMessages for recent etc).
/// ~23+ granular cbs total (onSave/onNotify removed in fix round 1: god owns
/// post-eval save/notify after pre-turn evals to avoid double in oneShot paths
/// and races; leaf populates pending snapshot for god to persist). Live closures
/// in god for test overrides + group per-speaker impersonation/load scalars
/// without cycles; testable with small factory in dedicated test.
///
/// 1:1 vs group + oneShot vs normal parity 1:1 equivalent deltas/behavior at all
/// times (Realism Engine bond/trust ±300/±100 clamps, emotion, fixation, spatial,
/// time every-6, arousal; oneShot must match normal multi-call for the fields it
/// covers; Needs/Objectives parity via other paths but qualified here for any
/// overlap; dispatch preserved exactly via cbs + god impersonation dance +
/// loadGroupRealismIntoScalars before speaker evals). Qualified (preserved
/// exactly; exercised in dedicated + key suites + manual).
///
/// Dedicated test: test/services/chat/realism_evals_test.dart with factory
/// (createTestRealismEvals) using live closures over group maps + cbs (real
/// dispatch, no forcing god internals). 15-25+ test() bodies via live
/// `grep -c '^\s*test('` confirmed post mandatory dead noop/placeholder/vestigial/
/// factory-setup deletion *as part of task*. Coverage: public surface + roundtrips
/// + group vs 1:1 via cbs + edges (guards, !ready/cancel, empty, error, "none",
/// strip, impersonation/proposal parity, oneShot vs normal, Realism/Needs/Objectives
/// parity 1:1 equiv deltas, chips/sidebar/group per-char, no random, etc.).
///
/// aug/integration tests (realism_engine_test, group_realism_test, etc.): receive
/// *only* qualified passive notes in headers/comments (no realism-evals-specific
/// aug file logic edits; full coverage + edges + oneShot/normal + group per-char +
/// chips/sidebar + parity in dedicated + manual; "aug exercising only passive/qualified
/// (no realism-evals-specific aug file edits; full in dedicated realism_evals_test +
/// manual; exercised via god thins _evaluate*Call ; qualified notes only in dedicated
/// header + god + MD per precedent)".
///
/// 0 new god private _ methods (thins/delegates + late final only; the void _ count
/// grep stays at prior 15 confirmed after every edit + final; thins/calls/late final
/// + reset comment syncs only per plan).
/// Anti-accumulation: explicit dead code audit of affected in god (no new _Eval/
/// _Realism methods; old bodies excised).
/// Reset hygiene: stateless or prompt-only (no owned reset/seed/load state; no
/// reset calls needed on this leaf); god comments expanded to list + realism_evals
/// (stateless or prompt-only; no reset calls needed) alongside prior + cross-refs
/// (e.g. setActiveCharacter:1572); both startNew branches explicit; "incomplete
/// zeroing of secondary config on group/0-session/new-chat now complete" language
/// includes this leaf.
///
/// Header + god + test + MD all qualify the aug note (onSave/onNotify cbs removed
/// in fix round 1 for oneShot double-save hygiene; unexercised by design from leaf
/// in dedicated — god owns post-eval save/notify; exercised in prod + key suites).
///
/// Barrel: not added (internal to ChatService only; per checklist "unless 3+
/// locations"; opportunistic when touching for other reason).
class RealismEvals {
  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })
  fireLLMEval;

  // ── Tool-calling transport (realism_tools.dart) ──
  // Tools are a reliable way to obtain the SAME JSON the evals have always
  // parsed: a successful call is converted to canonical flat-JSON text and
  // flows through the unchanged pipeline (batch collect → verifier → regex
  // extractors → appliers), so one-shot/multi-call and 1:1/group parity hold
  // by construction. Backends that fail the probe fall back to the streaming
  // text path — probe memory is shared with the Journal + Growth passes.
  final Future<LlmToolResponse?> Function(
    String prompt,
    List<Map<String, dynamic>> tools,
  )
  fireToolEval;
  final ToolTransportProbe probe;
  final String Function() getBackendIdentity;

  /// Live cancel check for the (non-streaming) tools attempt: a user cancel
  /// aborts the backend request, which must read as "cancelled", never as
  /// "this backend can't do tools".
  final bool Function() isEvalCancelled;

  final String Function(String) stripThinkBlocks;
  final int? Function(String, String) extractJsonInt;
  final bool? Function(String, String) extractJsonBool;

  // Character / group / mode state (for guard + 1:1 vs group dispatch via impersonation)
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;

  // User / persona for eval prompts
  final String Function() getUserName;

  // Realism flag
  final bool Function() getRealismEnabled;

  // Optional verifier (director) thread. When the per-char flag is on, called after fire+strip
  // with the *full* latent decision context so it can validate + correct or reprocess.
  // Provided by god (late final RealismVerification instance or thin wrapper); passthrough when off.
  // 1:1/group/oneShot parity via the same cbs + impersonation dance used for the 5 evals.
  final Future<VerificationResult> Function({
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
  })?
  verifyRealismOutput;

  // Support for the "fire the 5 mains (parallel), then one director/verifier pass on the whole set"
  // (user proposal to cut roundtrips on remote APIs when per-char realismVerificationEnabled is on).
  // beginCollectForBatchedVerification() is called by god before the 4-eval Future.wait (only in !oneShot path).
  // The evaluate* methods short-circuit their per-eval _verifyAndApply + parse when the flag is active,
  // stashing raw + context into _pendingBatchEvals. finalize flips the flag off (god then pulls via
  // getCollectedForBatch, runs verifyBatch on the god _realismVerifier for at most one combined critique,
  // then applyBatchResults which does the per-kind parse/side-effects using corrected or original eff).
  // The fast-path (flag off, the common case) is inside verifyBatch itself (returns accepted map of
  // originals with zero LLM cost or captures); apply then drives the normal _parseAndApplyRelationshipDeltas
  // etc. so bond/trust/arousal (Lust) chips, emotion, fixation, and autonomous objectives are produced exactly
  // as the direct paths. Physical stays delegated; oneShot path stays single-eval for now.
  bool _batchCollectActive = false;
  final List<Map<String, dynamic>> _pendingBatchEvals = []; // kind, stripped, prompt, scene, injections (for batch director after mains)

  void beginCollectForBatchedVerification() {
    _batchCollectActive = true;
    _pendingBatchEvals.clear();
  }

  Future<void> finalizeBatchedRealismVerifications() async {
    _batchCollectActive = false;
    // Do NOT clear _pendingBatchEvals here.
    // God (chat_service) follows with:
    //   final collected = _realismEvals.getCollectedForBatch();
    //   if (collected.isNotEmpty) {
    //     ... map to items ...
    //     final batchRes = await _realismVerifier.verifyBatch(items);
    //     await _realismEvals.applyBatchResults(batchRes);
    //   }
    // This is what feeds _parseAndApplyRelationshipDeltas (bond/trust/arousal deltas + pending
    // for chips) and the emotional/narrative side effects for the !oneShot pre-response path.
    // The previous unconditional clear here (plus wouldVerify early-out) caused collected to
    // always be empty for the default 4-eval path, so the parse/apply never ran and bond/trust/lust
    // delta chips stopped appearing (only the post-eval emotion_label synthesis remained).
    // verifyBatch itself provides the cheap no-op (accepted originals, no LLM) when the per-char
    // realismVerificationEnabled flag is off.
  }

  List<Map<String, dynamic>> getCollectedForBatch() => List<Map<String, dynamic>>.from(_pendingBatchEvals);

  Future<void> applyBatchResults(Map<String, VerificationResult> results) async {
    // Snapshot to survive any concurrent mutation and to allow apply to clear at end.
    final pending = List<Map<String, dynamic>>.from(_pendingBatchEvals);
    for (final p in pending) {
      final kind = p['kind'] as String;
      final raw = p['raw'] as String;
      final eff = results[kind]?.correctedRaw ?? raw;
      switch (kind) {
        case 'relationship':
          _parseAndApplyRelationshipDeltas(eff);
          break;
        case 'emotional_state':
          await _applyEmotionalResults(eff);
          break;
        case 'narrative':
          await _applyNarrativeResults(eff);
          break;
        case 'oneShot':
          // Future-proof: oneShot path currently bypasses batch collection (god only begins
          // collect in the !oneShot 4-eval branch), but if collected treat as combined.
          _parseAndApplyRelationshipDeltas(eff);
          await _applyEmotionalResults(eff);
          await _applyNarrativeResults(eff);
          // posture/fixation/objective/reason handled inside _applyNarrative + rel parse
          break;
        default:
          break;
      }
    }
    _pendingBatchEvals.clear();
  }

  /// Apply emotional scalar + arousal pending updates from a (possibly corrected) eval text.
  /// Mirrors the direct-path logic after _verify in evaluateEmotionalStateCall so batch and
  /// direct produce identical emotion/arousal side effects and chip metadata.
  Future<void> _applyEmotionalResults(String text) async {
    final emotionMatch = RegExp(
      r'"emotion"\s*:\s*"([^"]+)"',
    ).firstMatch(text);
    if (emotionMatch != null) {
      setCharacterEmotion(emotionMatch.group(1)!.toLowerCase().trim());
    }

    final intensityMatch = RegExp(
      r'"emotion_intensity"\s*:\s*"([^"]+)"',
    ).firstMatch(text);
    if (intensityMatch != null) {
      setEmotionIntensity(intensityMatch.group(1)!.toLowerCase().trim());
    }

    if (nsfwService.nsfwCooldownEnabled) {
      final arDelta = extractJsonInt(text, 'arousal_delta');
      if (arDelta != null) {
        // Record the EFFECTIVE delta (post-clamp + refractory physiology) so
        // chips show what actually happened and regen revert stays exact.
        final arousalDelta = nsfwService.applyEvalArousalDelta(
          arDelta.clamp(kMinArousalDelta, kMaxArousalDelta),
        );
        if (arousalDelta != 0) {
          var pending = getPendingRealismMetadata() ?? {};
          pending['arousal_delta'] = arousalDelta;
          setPendingRealismMetadata(pending);
        }
      }
    }
  }

  /// Apply fixation update + autonomous objective proposal (if any) from a (possibly director-corrected)
  /// narrative eval text. Extracted here so the batch apply path can reuse the exact same
  /// side-effect logic (and dedup) without growing god or duplicating the json+regex fallbacks.
  Future<void> _applyNarrativeResults(String text) async {
    // Robust extraction (survives Director reprocess/correction which may reformat/partial JSON).
    // Inline (no new named helper/method per rules for god; private here in leaf is fine).
    // Parse JSON once (both keys live in the same payload) rather than twice.
    String fixationRaw = '';
    String objectiveRaw = '';
    try {
      final noFence = text.replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ').trim();
      final si = noFence.indexOf('{');
      final ei = noFence.lastIndexOf('}');
      if (si >= 0 && ei > si) {
        final obj = jsonDecode(noFence.substring(si, ei + 1));
        if (obj is Map) {
          if (obj['fixation_topic'] != null) fixationRaw = obj['fixation_topic'].toString().trim();
          if (obj['proposed_objective'] != null) objectiveRaw = obj['proposed_objective'].toString().trim();
        }
      }
    } catch (_) {}
    if (fixationRaw.isEmpty) {
      final m = RegExp('"fixation_topic"\\s*:\\s*"([^"]*)"', dotAll: true).firstMatch(text);
      fixationRaw = m?.group(1)?.trim() ?? '';
    }
    relationshipService.updateFixationFromEvalResult(fixationRaw.isNotEmpty ? fixationRaw : '');

    if (objectiveRaw.isEmpty) {
      final m2 = RegExp('"proposed_objective"\\s*:\\s*"([^"]*)"', dotAll: true).firstMatch(text);
      objectiveRaw = m2?.group(1)?.trim() ?? '';
    }
    if (objectiveRaw.toLowerCase() != 'none' && objectiveRaw.isNotEmpty) {
      final active = getActiveObjectives();
      final isDuplicate = active.any(
        (o) => o.objective.toLowerCase() == objectiveRaw.toLowerCase(),
      );
      if (!isDuplicate) {
        // Claim the main-quest slot when it's free: the character's self-initiated
        // goal becomes their driving primary quest with a full task arc. When a
        // primary already exists (user-set or an earlier autonomous quest), the
        // proposal stays a side quest — never displace an existing main quest.
        final becomesPrimary = getPrimaryObjective() == null;
        debugPrint(
          '[Realism:Narrative] Autonomous objective proposed: $objectiveRaw '
          '(${becomesPrimary ? "primary — main-quest slot free" : "secondary — primary exists"})',
        );
        // Pass autoGenerateTasks:true so the character's self-initiated goal gets
        // concrete subtasks (making autonomous objectives feel like real pursuits
        // with steps the character can accomplish).
        // (thin delegation to god setObjective per plan for step9; full proposal logic here)
        await setObjective(
          objectiveRaw,
          isPrimary: becomesPrimary,
          autoGenerateTasks: true,
        );
      }
    }
  }

  // Messages for recent context in evals
  final List<ChatMessage> Function() getMessages;

  // Pending metadata + capture for realism state snapshot (oneShot + rel/emotion)
  final Map<String, dynamic>? Function() getPendingRealismMetadata;
  final void Function(Map<String, dynamic>?) setPendingRealismMetadata;
  final Map<String, dynamic> Function({Map<String, int>? preTurn})
  captureRealismState;

  // Emotion scalars set by evals (1:1 + group speaker after impersonation)
  final String Function() getCharacterEmotion;
  final void Function(String) setCharacterEmotion;
  final String Function() getEmotionIntensity;
  final void Function(String) setEmotionIntensity;

  // Services for owned state (avoids duplicating scalars/cbs in god for this leaf)
  final RelationshipService relationshipService;
  final NsfwService nsfwService;
  final TimeService timeService;

  // Expression enabled for the "MUST choose label from list" instruction in emotion prompts
  final bool Function() getExpressionEnabled;

  // Character dossier for the judge prompts (personality + description +
  // evolution growth, budget-capped via RealismPromptBuilder.characterDossier).
  // Wired by god so group impersonation (card = current speaker) and the
  // evolution-enabled flag are respected. This is what lets the evals judge
  // through the character's full identity instead of the raw personality
  // field alone (which many cards leave empty).
  final String Function(CharacterCard card) getCharacterDossier;

  // Objective proposal (for narr/oneShot; thin cb to god per plan for coordination)
  final Objective? Function() getPrimaryObjective;
  final List<Objective> Function() getActiveObjectives;
  final Future<void> Function(
    String objectiveText, {
    bool isPrimary,
    bool autoGenerateTasks,
  })
  setObjective;

  RealismEvals({
    required this.fireLLMEval,
    required this.fireToolEval,
    required this.probe,
    required this.getBackendIdentity,
    required this.isEvalCancelled,
    required this.stripThinkBlocks,
    required this.extractJsonInt,
    required this.extractJsonBool,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getUserName,
    required this.getRealismEnabled,
    required this.getMessages,
    required this.getPendingRealismMetadata,
    required this.setPendingRealismMetadata,
    required this.captureRealismState,
    required this.getCharacterEmotion,
    required this.setCharacterEmotion,
    required this.getEmotionIntensity,
    required this.setEmotionIntensity,
    required this.relationshipService,
    required this.nsfwService,
    required this.timeService,
    required this.getExpressionEnabled,
    required this.getCharacterDossier,
    required this.getPrimaryObjective,
    required this.getActiveObjectives,
    required this.setObjective,
    this.verifyRealismOutput,
  });

  /// Pre-parse fire for the JSON evals — thin over the ONE shared
  /// negotiation ([fireStructuredEval] in pass_support.dart): tools first
  /// when the backend allows (canonical JSON synthesized from the call via
  /// realism_tools), text-reply salvage, streaming text fallback otherwise.
  Future<String?> _fireEval({
    required String toolName,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
    void Function(String)? onChunk,
  }) => fireStructuredEval(
    probe: probe,
    backendIdentity: getBackendIdentity(),
    debugLabel: toolName,
    tools: tools,
    buildPrompt: buildPrompt,
    callToText: (resp) => realismToolCallToJson(toolName, resp.calls),
    fireToolEval: fireToolEval,
    fireTextEval: fireLLMEval,
    isCancelled: isEvalCancelled,
    onChunk: onChunk,
  );

  /// Shared post-fire verifier wrapper (used by all 5 realism paths + oneShot).
  /// Assembles the rich latent bundle from what this leaf just used (prompt, pre via capture cb,
  /// active char, messages, scene from recent or passed response context) and calls the verify cb if present.
  /// Returns the (possibly corrected) text for downstream parse/apply, and attaches verification
  /// metadata to pending for the message bubble chip.
  /// 1:1/group dispatch and pre state are handled by the cbs (god impersonation dance ensures correct card + pre-decay snapshot).
  Future<String> _verifyAndApply({
    required String evalKind,
    required String textAfterStrip,
    required String promptUsed,
    required String sceneForContext,
    Map<String, String>? injections,
  }) async {
    if (verifyRealismOutput == null) return textAfterStrip;

    // Fast-path when the per-character "Director / Verifier" (realismVerificationEnabled) is off
    // (the default). This skips expensive work that was previously done for every one of the
    // 5 pre-response realism evals (and the post-gen needs impact): captureRealismState() (full
    // scalar + needs vector + time snapshot), getMessages() list, frontPorchExtensions.toJson(),
    // building the rich latent bundle, etc. The inner verifier also early-returns when disabled,
    // but we avoid the call-site cost entirely. On remote APIs (e.g. nano-gpt) this keeps the
    // "Realism Engine processing" phase for the 5 evals at the original speed. When the flag is
    // on for a character (opt-in for higher-fidelity reviewed deltas), the full verification
    // (rule checks + possible LLM critique + re-fire up to max reprocesses) still runs.
    final char = getActiveCharacter();
    final verifOn = (char?.frontPorchExtensions?.realismVerificationEnabled ?? false) &&
        getRealismEnabled() &&
        (getActiveGroup() == null || !getIsObserverMode());
    if (!verifOn) return textAfterStrip;

    try {
      final vres = await verifyRealismOutput!(
        evalKind: evalKind,
        rawOutput: textAfterStrip,
        sceneResponse: sceneForContext,
        preState: captureRealismState(),
        activeChar: getActiveCharacter(),
        activeGroup: getActiveGroup(),
        recentMessages: getMessages(),
        promptText: promptUsed,
        injections: injections ?? const <String, String>{},
        strictnessOverride: null, // leaf uses live cb inside verifier
        maxPassesOverride: null,
      );
      if (vres.status.isNotEmpty) {
        // Attach for bubble chip (and any sidebar notes). God will also stamp on the final ChatMessage.
        final current = (getPendingRealismMetadata() ?? <String, dynamic>{});
        current[RealismVerification.kMetaKey] = vres.toMetadata();
        setPendingRealismMetadata(current);
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

  /// Parses relationship/trust (+ best-effort or requested arousal) fields from
  /// an eval JSON text, applies the side effects (score/trust deltas to services,
  /// arousal to nsfwService), populates pending metadata for chips/reasons using
  /// only nonzero deltas (reasons are populated when present even if deltas are 0),
  /// and returns the resolved values for caller debug logging.
  ///
  /// This single implementation is used by both the separate relationship eval
  /// (multi-call) and the fused one-shot eval, guaranteeing identical clamp
  /// behavior and pending population for bond/trust/arousal.
  ({
    int bondDelta,
    int trustDelta,
    int arousalDelta,
    String bondReason,
    String trustReason,
  })
  _parseAndApplyRelationshipDeltas(String text) {
    // Bond / relationship delta (per prompt range)
    final relDelta = extractJsonInt(text, 'relationship_delta');
    int bondDelta = 0;
    if (relDelta != null) {
      bondDelta = relDelta.clamp(kMinRelationshipDelta, kMaxRelationshipDelta);
      relationshipService.applyScoreDelta(bondDelta);
    }

    // Trust delta (user behavior only; per prompt range)
    int trustDelta = 0;
    final trDelta = extractJsonInt(text, 'trust_delta');
    if (trDelta != null) {
      trustDelta = trDelta.clamp(kMinTrustDelta, kMaxTrustDelta);
      if (trustDelta != 0) {
        relationshipService.applyTrustDelta(trustDelta);
      }
    }

    // Arousal (only when NSFW cooldowns are enabled; relationship path treats
    // as best-effort since its prompt does not request the field; emotional and
    // one-shot paths request it when enabled). arousalDelta ends up holding the
    // EFFECTIVE delta (post-clamp + refractory physiology) so pending metadata,
    // chips, and regen revert all agree on what actually landed.
    int arousalDelta = 0;
    if (nsfwService.nsfwCooldownEnabled) {
      final arDelta = extractJsonInt(text, 'arousal_delta');
      if (arDelta != null) {
        arousalDelta = nsfwService.applyEvalArousalDelta(
          arDelta.clamp(kMinArousalDelta, kMaxArousalDelta),
        );
      }
    }

    // Nonzero deltas → pending (for chips + message metadata). Only record
    // nonzero so UI and revert logic stay uncluttered (0s are the default).
    // Exception for trust: always record the trust_delta and trust_reason from the
    // relationship eval (even 0) if the eval produced a non-"none" reason. This makes
    // "Trust: 0 (He embraced my filth without judgment — that built something real)"
    // visible and revertible, fixing cases where trust movement was "dropped" from
    // metadata/synthesis/attachment/logs on accepted verifier output for deep
    // acceptance scenes.
    if (bondDelta != 0 || arousalDelta != 0 || trustDelta != 0) {
      var pending = getPendingRealismMetadata() ?? {};
      if (bondDelta != 0) pending['bond_delta'] = bondDelta;
      if (arousalDelta != 0) pending['arousal_delta'] = arousalDelta;
      // Always record trust_delta from the relationship eval (even 0) so that
      // "Trust: 0 (reason)" from deep acceptance scenes is carried to metadata,
      // synthesis, attachment, chips, and revert. The previous !=0 guard was
      // the direct cause of "trust delta dropped" in logs and pending.
      pending['trust_delta'] = trustDelta;
      setPendingRealismMetadata(pending);
    }

    // Reasons (for hover tooltips on chips). Always extract; set if present
    // and not the sentinel "none".
    final bondReasonMatch = RegExp(
      r'"bond_reason"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final rawBondReason = bondReasonMatch?.group(1)?.trim() ?? '';
    final bondReason = rawBondReason.toLowerCase() == 'none'
        ? ''
        : rawBondReason;
    if (bondReason.isNotEmpty) {
      var pending = getPendingRealismMetadata() ?? {};
      pending['bond_reason'] = bondReason;
      setPendingRealismMetadata(pending);
    }

    final trustReasonMatch = RegExp(
      r'"trust_reason"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final rawTrustReason = trustReasonMatch?.group(1)?.trim() ?? '';
    final trustReason = rawTrustReason.toLowerCase() == 'none'
        ? ''
        : rawTrustReason;
    if (trustReason.isNotEmpty) {
      var pending = getPendingRealismMetadata() ?? {};
      pending['trust_reason'] = trustReason;
      setPendingRealismMetadata(pending);
    }

    return (
      bondDelta: bondDelta,
      trustDelta: trustDelta,
      arousalDelta: arousalDelta,
      bondReason: bondReason,
      trustReason: trustReason,
    );
  }

  // ── The 5 Realism Eval Calls (full bodies moved here from engine in step 10) ──

  Future<void> evaluateRelationshipCall({
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) {
      return; // Director excluded
    }

    final msgs = getMessages();
    final recentCount = msgs.length < 3 ? msgs.length : 3;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.promptText}')
        .join('\n');

    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final char = getActiveCharacter()!;
    final charName = char.name;
    final userName = getUserName();

    final dossier = getCharacterDossier(char);
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: relationshipService.shortTermTierName,
      longTermTier: relationshipService.longTermTierName,
      trustTier: relationshipService.trustTierName,
      trustLevel: relationshipService.trustLevel,
      emotion: getCharacterEmotion(),
      emotionIntensity: getEmotionIntensity(),
    );

    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.relationshipEvalPrompt(
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

    try {
      debugPrint('[Realism] Evaluating relationship dynamic...');
      final raw = await _fireEval(
        toolName: kRelationshipTool,
        tools: kRelationshipEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) return;

      final searchText = stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      // Verifier (if wired and per-char enabled): receives full latent (prompt + pre + char + *all* injections at fire + scene + kind).
      // Effective text (original or corrected) used for parse/apply/side effects + metadata for chip.
      if (_batchCollectActive) {
        _pendingBatchEvals.add({
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

      final effectiveText = await _verifyAndApply(
        evalKind: 'relationship',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {'personality': dossier, 'standing': standing},
      );

      // Unified parse/apply (also used by one-shot). The relationship path passes
      // arousal parsing through even though its prompt does not request the field
      // (best-effort extraction preserved exactly).
      final res = _parseAndApplyRelationshipDeltas(effectiveText);

      debugPrint(
        '[Realism:Relationship] Bond: ${res.bondDelta} (${res.bondReason.isNotEmpty ? res.bondReason : 'no reason'}) | Trust: ${res.trustDelta} (${res.trustReason.isNotEmpty ? res.trustReason : 'no reason'})',
      );
      debugPrint(
        '[Realism:Metadata] _pendingRealismMetadata after relationship eval: ${getPendingRealismMetadata()}',
      );
    } catch (e) {
      debugPrint('[Realism:Relationship] Failed: $e');
    }
  }

  Future<void> evaluateEmotionalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;
    final msgs = getMessages();
    final recentCount = msgs.length < 4 ? msgs.length : 4;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.promptText}')
        .join('\n');
    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final char = getActiveCharacter()!;
    final charName = char.name;
    final userName = getUserName();

    final dossier = getCharacterDossier(char);
    // Previous-turn mood rides the standing line so the judge names the new
    // emotion with natural inertia instead of re-deciding from scratch.
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: relationshipService.shortTermTierName,
      longTermTier: relationshipService.longTermTierName,
      trustTier: relationshipService.trustTierName,
      trustLevel: relationshipService.trustLevel,
      emotion: getCharacterEmotion(),
      emotionIntensity: getEmotionIntensity(),
    );
    final arousalEnabled = nsfwService.nsfwCooldownEnabled;
    final labels = getExpressionEnabled() ? EmotionLabels.all : const <String>[];

    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.emotionalEvalPrompt(
          charName: charName,
          userName: userName,
          dossier: dossier,
          standing: standing,
          recent: recent,
          arousalEnabled: arousalEnabled,
          arousalLevel: nsfwService.arousalLevel,
          refractoryTurnsLeft: nsfwService.cooldownTurnsRemaining,
          allowedEmotionLabels: labels,
          toolsMode: toolsMode,
        );
    final prompt = buildPrompt(toolsMode: false);

    try {
      debugPrint(
        '[Realism] Evaluating emotional state... '
        '(nsfwArousal=${nsfwService.nsfwCooldownEnabled}, '
        'arousalLevel=${nsfwService.arousalLevel})',
      );
      final raw = await _fireEval(
        toolName: kEmotionalTool,
        tools: kEmotionalEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) return;

      final searchText = stripThinkBlocks(raw);
      var text = searchText.isNotEmpty ? searchText : raw;

      if (_batchCollectActive) {
        _pendingBatchEvals.add({
          'kind': 'emotional_state',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {
            'personality': dossier,
            'standing': standing,
            if (labels.isNotEmpty)
              'emotion_constraint':
                  RealismPromptBuilder.emotionLabelConstraint(labels),
          },
        });
        return;
      }

      final effectiveText = await _verifyAndApply(
        evalKind: 'emotional_state',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {
          'personality': dossier,
          'standing': standing,
          if (labels.isNotEmpty)
            'emotion_constraint':
                RealismPromptBuilder.emotionLabelConstraint(labels),
        },
      );
      text = effectiveText; // rebind (var allows)

      await _applyEmotionalResults(text);
      debugPrint(
        '[Realism:Emotion] Emotion: ${getCharacterEmotion()} (${getEmotionIntensity()})',
      );
    } catch (e) {
      debugPrint('[Realism:Emotion] Failed: $e');
    }
  }

  Future<void> evaluatePhysicalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;

    final msgs = getMessages();
    final recentCount = msgs.length < 6 ? msgs.length : 6;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.promptText}')
        .join('\n');
    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet.
      // (Time advance is chat-scoped and handled via delegation when active char is impersonated for group speaker.)
      return;
    }
    final charName = getActiveCharacter()!.name;

    // Time progress + posture (when passage enabled) + disabled-passage posture path
    // now fully delegated to TimeService (pre-turn advance logic moved verbatim,
    // adjusted only for granular cbs). No new private method in god.
    // shortTermTierName resolves via relationshipService.
    await timeService.evaluateTimeProgressAndPostureIfNeeded(
      charName: charName,
      recent: recent,
      shortTermTierName: relationshipService.shortTermTierName,
      onChunk: onChunk,
      fireLLMEval: fireLLMEval,
      stripThinkBlocks: stripThinkBlocks,
      extractJsonBool: extractJsonBool,
      setSpatialStance: relationshipService.setSpatialStance,
      getCurrentSpatialStance: () => relationshipService.spatialStance,
      getCharacterEmotion: getCharacterEmotion,
      getEmotionIntensity: getEmotionIntensity,
    );
  }

  Future<void> evaluateNarrativeCall({void Function(String)? onChunk}) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;
    final msgs = getMessages();
    final recentCount = msgs.length < 4 ? msgs.length : 4;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.promptText}')
        .join('\n');
    if (getActiveCharacter() == null) {
      // This path requires an active character (the group per-speaker path
      // temporarily sets _activeCharacter before calling us for parity).
      return;
    }
    final char = getActiveCharacter()!;
    final charName = char.name;
    final userName = getUserName();
    final primary = getPrimaryObjective();

    final dossier = getCharacterDossier(char);
    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.narrativeEvalPrompt(
          charName: charName,
          userName: userName,
          dossier: dossier,
          recent: recent,
          primaryObjective: primary?.objective,
          toolsMode: toolsMode,
        );
    final prompt = buildPrompt(toolsMode: false);

    try {
      final raw = await _fireEval(
        toolName: kNarrativeTool,
        tools: kNarrativeEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) return;
      var text = stripThinkBlocks(raw).isNotEmpty ? stripThinkBlocks(raw) : raw;
      if (_batchCollectActive) {
        _pendingBatchEvals.add({
          'kind': 'narrative',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {'personality': dossier},
        });
        return;
      }

      final effectiveText = await _verifyAndApply(
        evalKind: 'narrative',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {'personality': dossier},
      );
      text = effectiveText; // rebind for downstream (no other code change)

      await _applyNarrativeResults(text);
    } catch (e) {
      debugPrint('[Realism:Narrative] Failed: $e');
    }
  }

  /// ── One-Shot Eval (Experimental) ─────────────────────────────────────────
  /// Fused replacement for _evaluateRelationshipCall + _evaluateSceneStateCall.
  /// Issues a SINGLE LLM inference that evaluates all realism state fields at
  /// once, cutting pre-generation blocking overhead from 2 calls to 1.
  ///
  /// Enable via Settings → Realism → "One-Shot Eval (Experimental)".
  /// Not default because some models struggle with the combined prompt length.
  Future<void> evaluateOneShotCall({void Function(String)? onChunk}) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;

    // The group speaker path sets _activeCharacter before calling this for parity.

    // Keep the eval prompt lean for local models — use fewer messages and a
    // shorter personality snippet to reduce prefill time on large models.
    final msgs = getMessages();
    final recentCount = msgs.length < 6 ? msgs.length : 6;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.promptText}')
        .join('\n');

    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final char = getActiveCharacter()!;
    final charName = char.name;
    final userName = getUserName();

    final dossier = getCharacterDossier(char);
    final standing = RealismPromptBuilder.standingContext(
      charName: charName,
      userName: userName,
      shortTermTier: relationshipService.shortTermTierName,
      longTermTier: relationshipService.longTermTierName,
      trustTier: relationshipService.trustTierName,
      trustLevel: relationshipService.trustLevel,
      emotion: getCharacterEmotion(),
      emotionIntensity: getEmotionIntensity(),
      posture: relationshipService.spatialStance,
    );
    final arousalEnabled = nsfwService.nsfwCooldownEnabled;
    final labels = getExpressionEnabled() ? EmotionLabels.all : const <String>[];
    final primary = getPrimaryObjective();

    // Same shared fragments as the multi-call path (strict one-shot vs normal
    // parity by construction — the rubric text cannot drift between paths).
    String buildPrompt({required bool toolsMode}) =>
        RealismPromptBuilder.oneShotEvalPrompt(
          charName: charName,
          userName: userName,
          dossier: dossier,
          standing: standing,
          recent: recent,
          arousalEnabled: arousalEnabled,
          arousalLevel: nsfwService.arousalLevel,
          refractoryTurnsLeft: nsfwService.cooldownTurnsRemaining,
          allowedEmotionLabels: labels,
          primaryObjective: primary?.objective,
          toolsMode: toolsMode,
        );
    final prompt = buildPrompt(toolsMode: false);

    try {
      debugPrint('[Realism:OneShot] Evaluating (fused call)...');
      final raw = await _fireEval(
        toolName: kOneShotTool,
        tools: kOneShotEvalTools,
        buildPrompt: buildPrompt,
        onChunk: onChunk,
      );
      if (raw == null) return;

      final searchText = stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      if (_batchCollectActive) {
        _pendingBatchEvals.add({
          'kind': 'oneShot',
          'raw': text,
          'prompt': prompt,
          'scene': recent,
          'injections': {
            'personality': dossier,
            'standing': standing,
            if (labels.isNotEmpty)
              'emotion_constraint':
                  RealismPromptBuilder.emotionLabelConstraint(labels),
          },
        });
        return;
      }

      final effectiveText = await _verifyAndApply(
        evalKind: 'oneShot',
        textAfterStrip: text,
        promptUsed: prompt,
        sceneForContext: recent,
        injections: {
          'personality': dossier,
          'standing': standing,
          if (labels.isNotEmpty)
            'emotion_constraint':
                RealismPromptBuilder.emotionLabelConstraint(labels),
        },
      );
      final textForOneShot = effectiveText; // rebind

      // ── Relationship / trust / arousal (unified with multi-call path) ──
      _parseAndApplyRelationshipDeltas(textForOneShot);

      // ── Autonomous Objective ──
      // (All parses below use textForOneShot — the Director-corrected text.
      // Parsing the raw pre-verification text silently discarded corrections
      // for everything except the relationship deltas.)
      final objectiveMatch = RegExp(
        r'"proposed_objective"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      if (objectiveMatch != null) {
        final newObj = objectiveMatch.group(1)!.trim();
        if (newObj.toLowerCase() != 'none' && newObj.isNotEmpty) {
          // Avoid setting the exact same goal if it's already active
          final active = getActiveObjectives();
          final isDuplicate = active.any(
            (o) => o.objective.toLowerCase() == newObj.toLowerCase(),
          );
          if (!isDuplicate) {
            // Same decision as the narrative path (strict oneShot vs normal parity):
            // claim the main-quest slot when it's free, stay a side quest when a
            // primary already exists — never displace an existing main quest.
            final becomesPrimary = getPrimaryObjective() == null;
            debugPrint(
              '[Realism:OneShot] Autonomous objective proposed: $newObj '
              '(${becomesPrimary ? "primary — main-quest slot free" : "secondary — primary exists"})',
            );
            // Pass autoGenerateTasks:true so the character's self-initiated goal gets
            // concrete subtasks (making autonomous objectives feel like real pursuits
            // with steps the character can accomplish).
            // (thin delegation to god setObjective per plan for step9)
            await setObjective(
              newObj,
              isPrimary: becomesPrimary,
              autoGenerateTasks: true,
            );
          }
        }
      }

      // ── Scene fields ──
      final emotionMatch = RegExp(
        r'"emotion"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      if (emotionMatch != null) {
        setCharacterEmotion(emotionMatch.group(1)!.toLowerCase().trim());
      }

      final intensityMatch = RegExp(
        r'"emotion_intensity"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      if (intensityMatch != null) {
        setEmotionIntensity(intensityMatch.group(1)!.toLowerCase().trim());
      }

      final postureMatch = RegExp(
        r'"posture"\s*:\s*"([^"]+)"',
      ).firstMatch(textForOneShot);
      if (postureMatch != null) {
        final p = postureMatch.group(1)!.trim();
        relationshipService.setSpatialStance(p);
      }

      relationshipService.updateFixationFromEvalResult(
        (RegExp(
              r'"fixation_topic"\s*:\s*"([^"]+)"',
            ).firstMatch(textForOneShot)?.group(1) ??
            ''),
        isOneShot: true,
      );

      // ── Story clock (parity with the multi-call path) ──
      // The fused JSON above already carries minutes_elapsed/new_day (and
      // posture); this applies the same clamp/floor/backstop clock math the
      // dedicated per-turn scene-time eval uses — no extra LLM call.
      await timeService.evaluateTimeProgressAndPostureIfNeeded(
        charName: charName,
        recent: recent,
        shortTermTierName: relationshipService.shortTermTierName,
        onChunk: onChunk,
        fireLLMEval: fireLLMEval,
        stripThinkBlocks: stripThinkBlocks,
        extractJsonBool: extractJsonBool,
        setSpatialStance: relationshipService.setSpatialStance,
        getCurrentSpatialStance: () => relationshipService.spatialStance,
        getCharacterEmotion: getCharacterEmotion,
        getEmotionIntensity: getEmotionIntensity,
        oneShotMode: true,
        oneShotText: textForOneShot,
      );

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(textForOneShot);
      debugPrint(
        '[Realism:OneShot] Done — Emotion: ${getCharacterEmotion()} (${getEmotionIntensity()}), '
        'Time: ${timeService.timeOfDay}, Reason: ${reasonMatch?.group(1) ?? 'unknown'}',
      );

      // Bundle full state snapshot for time-travel forking (god will persist via
      // post-eval _saveChat + synthesize in the calling pre-gen / baseline paths;
      // removing the cb calls here eliminates double save/notify for oneShot vs
      // multi-call paths and the save-race window).
      var pending = getPendingRealismMetadata() ?? {};
      pending['emotion_label'] = getCharacterEmotion();
      pending['realism_state'] = captureRealismState();
      setPendingRealismMetadata(pending);
    } catch (e) {
      debugPrint(
        '[Realism:OneShot] Failed: $e — falling back to dual-call on next turn',
      );
    }
  }
}
