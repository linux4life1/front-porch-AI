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

// Stage words come from AmbitionService so the eval prompt, the per-turn
// ambition injection and the journal progress cards all describe the same
// progress with the same word. A local copy here would drift the first time a
// band moved.
import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/services/chat/preference_scoring.dart';

part 'realism_prompt_builder.fragments.dart';

/// Per-eval delta limits for the realism LLM calls (relationship, emotional
/// state, one-shot). These are the authoritative ranges for what each eval is
/// allowed to contribute in a single turn. They are used both for .clamp()
/// enforcement (in realism_evals / realism_verification) and interpolated into
/// the prompt guidance text here, so the model instructions and the runtime
/// guard cannot drift from each other (or between the multi-call paths and the
/// fused one-shot path). Re-exported by realism_evals.dart for existing
/// importers.
const kMinRelationshipDelta = -15;
const kMaxRelationshipDelta = 15;
const kMinTrustDelta = -200;
const kMaxTrustDelta = 50;
const kMinArousalDelta = -25;
const kMaxArousalDelta = 25;

/// Single source of truth for the Realism Engine judge prompts.
///
/// Every fragment that appears in more than one eval (the bond and trust
/// rubrics, the emotion/arousal instructions, the objective/fixation asks) is
/// built exactly once here and composed into the full prompts for both the
/// multi-call path (relationship / emotional / narrative) and the fused
/// one-shot path — so the strict one-shot vs normal parity rule holds by
/// construction instead of by hand-synced copies.
///
/// Design principle (the "real person" rule): the judge is framed as the
/// character's own inner voice and is given the character's actual identity
/// (the dossier: personality + description + evolution growth) plus the
/// current relationship standing. Scoring anchors are defined by how deeply a
/// moment lands FOR THIS CHARACTER — never by a universal "affection is good /
/// only rudeness is bad" scale. Unwanted affection can score negative; earned
/// respect on the character's own terms scores positive. No coercive floors
/// ("give at least +1") and no objective-morality gates ("only go negative if
/// the user was unkind") — those made every character melt under generic
/// niceness regardless of who they were.
///
/// Pure statics, no state, no side effects; trivially testable.
class RealismPromptBuilder {
  RealismPromptBuilder._();

  // ── Character dossier ──────────────────────────────────────────────────────

  /// Total character-context budget per eval prompt (chars). Generous enough
  /// that typical cards are included whole; caps only the pathological tail so
  /// local-model prefill stays sane across the per-turn eval calls.
  static const int kDossierBudget = 2000;
  static const int _personalityCap = 900;
  static const int _growthCap = 400;

  /// Builds the "who this character is" block for the judge prompts from the
  /// same sources the main generation sees: the card's personality and
  /// description plus the evolution growth text (pass '' when evolution is
  /// disabled or absent). Personality is prioritized (it is the distilled
  /// temperament), growth keeps its most recent tail, description fills the
  /// remaining budget. Returns '' when there is nothing to say.
  static String characterDossier({
    required String name,
    required String personality,
    required String description,
    String growth = '',
  }) {
    final p = personality.trim();
    final d = description.trim();
    final g = growth.trim();
    if (p.isEmpty && d.isEmpty && g.isEmpty) return '';

    var remaining = kDossierBudget;
    final parts = <String>[];

    if (p.isNotEmpty) {
      final t = _trimTo(
        p,
        _personalityCap < remaining ? _personalityCap : remaining,
      );
      parts.add(t);
      remaining -= t.length;
    }

    // Reserve the growth slice before description so a long description can
    // never squeeze out how the character has actually changed.
    String growthPart = '';
    if (g.isNotEmpty && remaining > 120) {
      growthPart = _trimTo(
        g,
        _growthCap < remaining ? _growthCap : remaining,
        fromEnd: true,
      );
      remaining -= growthPart.length;
    }

    if (d.isNotEmpty && remaining > 120) {
      parts.add(_trimTo(d, remaining));
    }

    if (growthPart.isNotEmpty) {
      parts.add(
        'How $name has genuinely changed through recent interactions (this builds on, not replaces, who they are):\n$growthPart',
      );
    }

    return 'Who $name is — judge every reaction through this; it outranks any generic norm:\n'
        '"""\n${parts.join('\n\n')}\n"""\n\n';
  }

  // ── Current standing (shared context line) ─────────────────────────────────

  /// One-line snapshot of where the relationship currently stands, so the
  /// judge can tell wanted intimacy from premature intimacy. Used by the
  /// relationship, emotional, and one-shot prompts. [posture] is read-only
  /// CONTEXT ("where they currently are"); no prompt here asks the judge to
  /// produce a posture any more — that moved to the post-generation pass.
  static String standingContext({
    required String charName,
    required String userName,
    required String shortTermTier,
    required String longTermTier,
    required String trustTier,
    required int trustLevel,
    String emotion = '',
    String emotionIntensity = '',
    String posture = '',
  }) {
    final emo = emotion.isNotEmpty
        ? ' $charName\'s current mood: $emotion${emotionIntensity.isNotEmpty ? ' ($emotionIntensity)' : ''}.'
        : '';
    final pos = posture.isNotEmpty ? ' Position: "$posture".' : '';
    return 'Where things stand between $charName and $userName: short-term tension "$shortTermTier", '
        'long-term bond "$longTermTier", trust "$trustTier" ($trustLevel/100).$emo$pos\n'
        'Weigh this turn against that standing — intimacy that fits a devoted bond is overstepping '
        'from a near-stranger, and a guarded character thaws in inches, not leaps.\n\n';
  }

  /// The expression-label constraint line (also handed to the verifier via the
  /// injections map so Director corrections respect the same label set).
  static String emotionLabelConstraint(List<String> labels) => labels.isEmpty
      ? ''
      : 'You MUST choose EXACTLY ONE of these labels: ${labels.join(", ")}. No other words allowed.';

  // ── Shared judgment fragments ──────────────────────────────────────────────

  /// The card's authored Likes & Dislikes, as ONE line the judge weighs.
  ///
  /// Scoring half of authored likes. Body lives in [PreferenceScoring.block]
  /// so this file does not grow; the name stays here so one-shot wiring
  /// cannot pick a second builder.
  static String preferencesBlock({
    required String charName,
    List<String> likes = const [],
    List<String> dislikes = const [],
    List<String> intimateInto = const [],
    List<String> intimateNotInto = const [],
    bool intimateAgency = false,
  }) => PreferenceScoring.block(
    charName: charName,
    likes: likes,
    dislikes: dislikes,
    intimateInto: intimateInto,
    intimateNotInto: intimateNotInto,
    intimateAgency: intimateAgency,
  );

  /// The ambitions the roster numbers — achieved ones are dropped, because a
  /// finished mountain has no next switchback and offering it invites the
  /// model to keep proposing steps toward something already done.
  ///
  /// Public because [resolveServedAmbition] is the inverse of the numbering
  /// this produces, and the two must read the same list. When they didn't,
  /// "2" would mean a different ambition on the way out than on the way back.
  static List<({String text, int progress})> openAmbitions(
    List<({String text, int progress})> ambitions,
  ) => [
    for (final a in ambitions)
      if (a.progress < 100) a,
  ];

  /// Turn a `serves_ambition` answer back into the ambition's TEXT, against
  /// the same roster the prompt numbered. Returns null for "none", junk, an
  /// out-of-range number, or a missing field — all of which mean the same
  /// thing downstream: this quest serves no ambition.
  ///
  /// Forgiving on purpose (local-model floor): a model that answers "2",
  /// "ambition 2", or "2 — open their own bakery" all resolve the same way.
  static String? resolveServedAmbition(
    String? raw,
    List<({String text, int progress})> ambitions,
  ) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty || text.toLowerCase().contains('none')) return null;
    final m = RegExp(r'\d+').firstMatch(text);
    if (m == null) return null;
    final idx = int.parse(m.group(0)!);
    final open = openAmbitions(ambitions);
    if (idx < 1 || idx > open.length) return null;
    return open[idx - 1].text;
  }

  // ── Full prompts (multi-call path + fused one-shot, parity by construction) ─

  /// The byte-identical PREFIX every judge prompt opens with: intro, dossier,
  /// standing, ambition roster, subjectivity frame. Everything eval-specific
  /// (the task line, the rubric sections, the recent window, the format ask)
  /// comes AFTER it.
  ///
  /// WHY IT EXISTS (eval review Tier-1 §3.3, maintainer-approved 2026-08-10):
  /// the three multi-call judges fire back-to-back into KoboldCpp's FIFO
  /// queue every turn, and each used to open with a DIFFERENT first sentence
  /// — so fast-forward was defeated from token one and every call re-prefilled
  /// its full copy of the same dossier/standing/frame. With a byte-identical
  /// prefix, call one pays the prefill and calls two and three fast-forward
  /// through it. The dispatch order in `_fireStaggeredRealismEvals` keeps the
  /// three prefix-sharing judges CONSECUTIVE (scene-time, whose prompt is
  /// deliberately lean and shares nothing, fires last) — firing order is
  /// free to change, eval PHASE is not (nothing moved across the generation
  /// boundary; the guard test pins both).
  ///
  /// Byte-identity holds only if the callers hand every judge the same
  /// inputs, which they do — same dossier/standing/preferences/ambitions
  /// callbacks, same 4-message window. The one-shot prompt opens with this
  /// same prefix (its standing additionally carries the posture line —
  /// irrelevant for caching, since one-shot REPLACES the trio, but the
  /// shared builder is what keeps the parity rule structural).
  ///
  /// The roster and frame render for every judge now (they used to be
  /// narrative-only and relationship/emotional-only respectively). That is
  /// deliberate: identical context is the price of a shared prefix, the
  /// blocks are self-omitting when empty (an ambition-less, preference-less
  /// card still costs what it did), and each is judge-relevant — the frame
  /// is the "real person" rule and the roster is who they are trying to
  /// become.
  static String judgePrefix({
    required String charName,
    required String userName,
    required String dossier,
    required String standing,
    String preferences = '',
    List<({String text, int progress})> ambitions = const [],
  }) =>
      'You are the private inner voice of $charName in a roleplay with '
      '$userName — the one who knows how each moment truly lands for them, '
      'what they feel, and what they want.\n\n'
      '$dossier'
      '$standing'
      '${_ambitionRoster(ambitions)}'
      '${_subjectivityFrame(charName, userName, preferences)}';

  static String relationshipEvalPrompt({
    required String charName,
    required String userName,
    required String dossier,
    required String standing,
    required String recent,
    String preferences = '',
    List<({String text, int progress})> ambitions = const [],
    bool toolsMode = false,
  }) =>
      '${judgePrefix(charName: charName, userName: userName, dossier: dossier, standing: standing, preferences: preferences, ambitions: ambitions)}'
      'Score how this exchange truly landed for $charName. Evaluate:\n'
      '${_bondSection(charName, userName)}'
      '${_trustSection(charName, userName)}'
      '\n'
      '${_recentBlock(recent)}'
      '${toolsMode ? _toolInstruction('report_relationship') : _jsonInstruction(const ['relationship_delta', 'bond_reason', 'trust_delta', 'trust_reason'])}';

  static String emotionalEvalPrompt({
    required String charName,
    required String userName,
    required String dossier,
    required String standing,
    required String recent,
    required bool arousalEnabled,
    required int arousalLevel,
    int refractoryTurnsLeft = 0,
    List<String> allowedEmotionLabels = const [],
    String preferences = '',
    List<({String text, int progress})> ambitions = const [],
    bool toolsMode = false,
  }) =>
      '${judgePrefix(charName: charName, userName: userName, dossier: dossier, standing: standing, preferences: preferences, ambitions: ambitions)}'
      'Name what $charName truly feels right now. Evaluate:\n'
      '${_emotionSection(charName, allowedEmotionLabels)}'
      '${arousalEnabled ? _arousalSection(charName, userName, arousalLevel, refractoryTurnsLeft) : ''}'
      '\n'
      '${_recentBlock(recent)}'
      '${toolsMode ? _toolInstruction('report_emotional_state') : _jsonInstruction(['emotion', 'emotion_intensity', if (arousalEnabled) 'arousal_delta'])}';

  static String narrativeEvalPrompt({
    required String charName,
    required String userName,
    required String dossier,
    required String recent,
    String standing = '',
    String preferences = '',
    String? primaryObjective,
    List<({String text, int progress})> ambitions = const [],
    bool toolsMode = false,
  }) =>
      '${judgePrefix(charName: charName, userName: userName, dossier: dossier, standing: standing, preferences: preferences, ambitions: ambitions)}'
      'Judge what $charName now wants and what lingers with them — both must '
      'fit who they are (their ambitions, wounds, and style), '
      'not generic story beats. Evaluate:\n'
      '${_objectiveSection(charName, userName, primaryObjective, ambitions)}'
      '${_fixationSection(charName)}'
      '\n'
      '${_recentBlock(recent)}'
      '${toolsMode ? _toolInstruction('report_narrative') : _jsonInstruction(['proposed_objective', if (_ambitionRoster(ambitions).isNotEmpty) 'serves_ambition', 'fixation_topic'])}';

  static String oneShotEvalPrompt({
    required String charName,
    required String userName,
    required String dossier,
    required String standing,
    required String recent,
    required bool arousalEnabled,
    required int arousalLevel,
    int refractoryTurnsLeft = 0,
    List<String> allowedEmotionLabels = const [],
    String? primaryObjective,
    List<({String text, int progress})> ambitions = const [],
    String preferences = '',
    bool toolsMode = false,
  }) =>
      '${judgePrefix(charName: charName, userName: userName, dossier: dossier, standing: standing, preferences: preferences, ambitions: ambitions)}'
      'Score how this exchange truly landed for $charName across every '
      'dimension below. Evaluate ALL of the following at once:\n'
      '${_bondSection(charName, userName)}'
      '${_trustSection(charName, userName)}'
      '${_emotionSection(charName, allowedEmotionLabels)}'
      '${arousalEnabled ? _arousalSection(charName, userName, arousalLevel, refractoryTurnsLeft) : ''}'
      '${_objectiveSection(charName, userName, primaryObjective, ambitions)}'
      '${_fixationSection(charName)}'
      '${_reasonSection()}'
      '\n'
      '${_recentBlock(recent)}'
      '${toolsMode ? _toolInstruction('report_realism') : _jsonInstruction(['relationship_delta', 'bond_reason', 'trust_delta', 'trust_reason', 'emotion', 'emotion_intensity', if (arousalEnabled) 'arousal_delta', 'proposed_objective', if (_ambitionRoster(ambitions).isNotEmpty) 'serves_ambition', 'fixation_topic', 'reason'])}';
}
