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

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart'
    show recentExchange, recentExchangeThroughLastUser;
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/utils/utils.dart';

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

part 'realism_evals.support.dart';
part 'realism_evals.calls.dart';
part 'realism_evals.one_shot.dart';

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
/// proposal in narr/oneShot, the clock + posture delegates to timeService which
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
  final Object fireToolEval;
  final ToolTransportProbe probe;
  final String Function() getBackendIdentity;
  final bool Function()? getPreferTextEvals;

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
  final List<Map<String, dynamic>> _pendingBatchEvals =
      []; // kind, stripped, prompt, scene, injections (for batch director after mains)

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

  List<Map<String, dynamic>> getCollectedForBatch() =>
      List<Map<String, dynamic>>.from(_pendingBatchEvals);

  Future<void> applyBatchResults(
    Map<String, VerificationResult> results,
  ) async {
    // Snapshot to survive any concurrent mutation and to allow apply to clear at end.
    final pending = List<Map<String, dynamic>>.from(_pendingBatchEvals);
    for (final p in pending) {
      final kind = p['kind'] as String;
      final raw = p['raw'] as String;
      final eff = results[kind]?.correctedRaw ?? raw;
      switch (kind) {
        // Arousal ownership mirrors the direct paths exactly (see the rule on
        // _parseAndApplyRelationshipDeltas): the eval that REQUESTS
        // arousal_delta applies it, nobody else.
        case 'relationship':
          _parseAndApplyRelationshipDeltas(eff, applyArousal: false);
          break;
        case 'emotional_state':
          await _applyEmotionalResults(eff, applyArousal: true);
          break;
        case 'narrative':
          await _applyNarrativeResults(eff);
          break;
        case 'oneShot':
          // Future-proof: oneShot path currently bypasses batch collection (god only begins
          // collect in the !oneShot 4-eval branch), but if collected treat as combined.
          // Both appliers read the SAME fused text here, so exactly one of
          // them may own arousal — the old true/true pair applied it twice.
          _parseAndApplyRelationshipDeltas(eff, applyArousal: true);
          await _applyEmotionalResults(eff, applyArousal: false);
          await _applyNarrativeResults(eff);
          // posture/fixation/objective/reason handled inside _applyNarrative + rel parse
          break;
        default:
          break;
      }
    }
    _pendingBatchEvals.clear();
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
  /// Whether Objectives are running for this chat (v45). The autonomous
  /// proposal is the one place a realism eval CREATES an objective, so it has
  /// to respect the Objectives switch — otherwise turning quests off would
  /// still grow new ones behind the user's back.
  final bool Function()? getObjectivesEnabled;
  final Objective? Function() getPrimaryObjective;
  final List<Objective> Function() getActiveObjectives;

  /// The evaluated speaker's ambitions with live progress — the mountain the
  /// proposal is asked to find the next switchback on (maintainer ruling
  /// 2026-08-07: ambitions guide objectives, not the other way around).
  ///
  /// Same source the sidebar and the web read, so what the model is shown and
  /// what the user is shown can never disagree. Empty (a character with no
  /// ambitions, or the getter absent) means the whole steering block and the
  /// `serves_ambition` field are omitted from the prompt entirely — that
  /// character's eval costs exactly what it did before this existed.
  final List<({String text, int progress})> Function()? getAmbitions;

  /// The evaluated speaker's authored Likes & Dislikes, already rendered to
  /// the ONE prompt line every judge sees (RealismPromptBuilder.preferencesBlock).
  ///
  /// Rendered by the caller rather than passed as four lists because the
  /// NSFW decision belongs upstream — this layer must not learn a second place
  /// to consult the 18+ switch. Absent or empty means the block is omitted
  /// entirely and that character's eval costs exactly what it did before,
  /// the same contract [getAmbitions] keeps.
  final String Function()? getPreferences;

  /// When true, one-shot tools/prompt include `today_sentence`. Default off.
  final bool Function()? getPlannerEnabled;

  final Future<void> Function(
    String objectiveText, {
    bool isPrimary,
    bool autoGenerateTasks,
    String? servedAmbition,
  })
  setObjective;

  RealismEvals({
    required this.fireLLMEval,
    required this.fireToolEval,
    required this.probe,
    required this.getBackendIdentity,
    this.getPreferTextEvals,
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
    this.getObjectivesEnabled,
    required this.getPrimaryObjective,
    required this.getActiveObjectives,
    this.getAmbitions,
    this.getPreferences,
    this.getPlannerEnabled,
    required this.setObjective,
    this.verifyRealismOutput,
  });
}
