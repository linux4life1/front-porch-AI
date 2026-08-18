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
import 'package:front_porch_ai/services/chat/preference_phrases.dart';

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

  /// Sentence-boundary-aware trim so capped card text never ends (or starts)
  /// mid-thought. [fromEnd] keeps the tail (used for growth, where the latest
  /// entries matter most).
  static String _trimTo(String text, int limit, {bool fromEnd = false}) {
    final t = text.trim();
    if (t.length <= limit) return t;
    const breaks = ['. ', '.\n', '! ', '? ', '\n'];
    if (fromEnd) {
      var cut = t.substring(t.length - limit);
      int firstBreak = -1;
      for (final b in breaks) {
        final i = cut.indexOf(b);
        if (i != -1 && (firstBreak == -1 || i < firstBreak)) firstBreak = i;
      }
      if (firstBreak != -1 && firstBreak < limit * 0.4) {
        cut = cut.substring(firstBreak + 1).trimLeft();
      }
      return '…$cut';
    }
    var cut = t.substring(0, limit);
    int lastBreak = -1;
    for (final b in breaks) {
      final i = cut.lastIndexOf(b);
      if (i > lastBreak) lastBreak = i;
    }
    if (lastBreak > limit * 0.6) {
      cut = cut.substring(0, lastBreak + 1);
    } else {
      final sp = cut.lastIndexOf(' ');
      if (sp > limit * 0.6) cut = cut.substring(0, sp);
    }
    return '${cut.trimRight()} …';
  }

  // ── Current standing (shared context line) ─────────────────────────────────

  /// One-line snapshot of where the relationship currently stands, so the
  /// judge can tell wanted intimacy from premature intimacy. Used by the
  /// relationship, emotional, and one-shot prompts. [posture] is read-only
  /// CONTEXT ("where she currently is"); no prompt here asks the judge to
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
  /// This is the SCORING half of the feature (the behavioural half is
  /// prompt_injection/preferences_injection.dart, which needs no engine). It
  /// makes [_subjectivityFrame]'s closing claim concrete: that paragraph
  /// already tells the model "what genuinely reaches someone is what THEY
  /// value" and then leaves it to guess what this particular character values.
  /// Now it does not have to.
  ///
  /// Rendered ONCE per turn and handed to all three prompts that carry the
  /// frame — relationship, emotional state, and the fused one-shot — so
  /// one-shot/multi-call parity holds by construction rather than by three
  /// copies that happen to match today (the strict-parity contract in
  /// CLAUDE.md).
  ///
  /// [intimateInto]/[intimateNotInto] are already NSFW-filtered by the caller;
  /// this builder does not consult a switch, so there is exactly one place
  /// that decision is made.
  ///
  /// Empty in, empty out: a character with no authored preferences costs their
  /// eval exactly what it cost before this existed — the same contract the
  /// ambition roster keeps.
  /// [intimateAgency] mirrors the After Dark "Acts on desires" switch (already
  /// AND-ed with the engine by the caller). It adds the refusal clause below —
  /// omitted when off, because a judge told to weigh "she asked and was
  /// refused" against a character who never asks is being asked to score
  /// something that did not happen.
  static String preferencesBlock({
    required String charName,
    List<String> likes = const [],
    List<String> dislikes = const [],
    List<String> intimateInto = const [],
    List<String> intimateNotInto = const [],
    bool intimateAgency = false,
  }) {
    // ONE shared cleanup with the behavioural injection (preference_phrases.dart)
    // so what the judge weighs and what the character was told cannot diverge —
    // and so a downloaded card's text cannot smuggle newlines into this prompt.
    final l = sanitizePreferencePhrases(likes);
    final d = sanitizePreferencePhrases(dislikes);
    final i = sanitizePreferencePhrases(intimateInto);
    final n = sanitizePreferencePhrases(intimateNotInto);
    if (l.isEmpty && d.isEmpty && i.isEmpty && n.isEmpty) return '';

    final parts = [
      if (l.isNotEmpty) 'drawn to ${l.join(', ')}',
      if (d.isNotEmpty) 'put off by ${d.join(', ')}',
      if (i.isNotEmpty) 'warms to ${i.join(', ')}',
      if (n.isNotEmpty) 'not interested in ${n.join(', ')}',
    ];
    return 'Specifically, $charName is ${parts.join('; ')}. '
        'Weigh the exchange against those: a moment that touches something they '
        'are drawn to lands harder than the same words otherwise would, and one '
        'that hits something they are put off by costs more — even when it was '
        'kindly meant. When one of these is what actually moved a score, SAY SO '
        'in that score\'s reason, naming it — the user sees those reasons and '
        'they are how a number stops being arbitrary. Do not invent preferences '
        'beyond these. '
        // The other half of "she acts on her desires" (preferences_injection).
        // She can now ask for what she wants; this is what makes the answer
        // MATTER. Without it a refusal reads to the judge as an ordinary line
        // of dialogue, emotion barely moves, and the next turn's mood line
        // shows a character who shrugged off being turned down — which is not
        // a character, it is a vending machine.
        //
        // Direction follows personality on purpose. "Refused, therefore angry"
        // would make every character the same character; the whole point of
        // the maintainer's example is that a DOMINANT one gets angry where a
        // gentler one goes quiet.
        '${intimateAgency ? 'When $charName asked for one of these and was refused — or was '
                  'given it — that is a real moment, not a neutral exchange. Score it '
                  'as one, and let the direction fit who they are: pressed and turned '
                  'down reads as anger or cold distance in a dominant character, and '
                  'as hurt or retreat in a gentler one. ' : ''}'
        '\n\n';
  }

  static String _subjectivityFrame(
    String charName,
    String userName,
    String preferences,
  ) =>
      'Score this exchange as $charName would privately feel it — through their personality, values, '
      'boundaries, and history — never by generic politeness.\n'
      'The same gesture lands differently on different people: affection, gifts, praise, or closeness '
      'only warm $charName if they are the kind of person who welcomes that, from $userName, at this '
      'point in the relationship. For a guarded, proud, dominant, aloof, or hostile character, unearned '
      'familiarity or smothering reads as cloying, presumptuous, or suspicious — score it neutral or '
      'negative no matter how kindly it was meant.\n'
      'What genuinely reaches someone is what THEY value: for one person open tenderness; for another, '
      'respect on their terms, competence, wit, backbone, obedience, patience, or being challenged.\n'
      '$preferences';

  static String _bondSection(String charName, String userName) =>
      '- "relationship_delta": how this exchange shifted $charName\'s genuine warmth toward $userName '
      '($kMinRelationshipDelta to +$kMaxRelationshipDelta).\n'
      '  Positive = it drew $charName closer by THEIR standards. Negative = it pushed them away — which '
      'includes well-meant gestures that trample their boundaries, pride, or pace, not only rudeness or cruelty.\n'
      '  Magnitude = how deeply the moment lands for $charName: ±1-2 barely registers | ±3-5 clearly felt | '
      '±6-9 strongly felt, stays with them | ±10-15 rare, relationship-redefining.\n'
      '  Most ordinary exchanges land between -2 and +2. 0 is the honest score when the turn simply '
      'didn\'t move $charName either way.\n'
      '- "bond_reason": one brief in-character thought from $charName explaining the shift '
      '(e.g. "They actually listened." or "Too much, too fast."), or "none" if the delta is 0.\n';

  static String _trustSection(String charName, String userName) =>
      '- "trust_delta": did $userName\'s behavior this turn give $charName reason to trust them more or '
      'less? ($kMinTrustDelta to +$kMaxTrustDelta)\n'
      '  Trust moves by $charName\'s own standards, and more slowly than warmth. Judge what THIS character '
      'would read as trustworthy:\n'
      '  · Honesty, kept promises, respected boundaries, steadiness, competence when it counted: +1 to +5 '
      'as small real deposits; +10 to +20 for something hard to fake (kept a difficult promise, stood firm '
      'under pressure); +30 to +50 only for extraordinary proof — real sacrifice, protection at cost, '
      'loyalty that cannot be faked.\n'
      '  · A wary, proud, or calculating character may read lavish gifts, flattery, or instant devotion as '
      'an angle being worked: for them that earns 0 — or -2 to -5 if it confirms their suspicions.\n'
      '  · For a character who welcomes warmth, small genuine care, reliability, and honest engagement DO '
      'accrue — bank a dependable +2 to +3 on any turn that genuinely goes well for them, not 0. Do not '
      'freeze their trust at 0 out of caution; reserve 0 for turns that were truly unremarkable or for the '
      'wary/calculating type above.\n'
      '  · Letdowns, evasiveness, pushing past a "no", broken small promises: -2 to -5. Deliberate '
      'deception or betrayal: -30 and beyond; $kMinTrustDelta is reserved for the unforgivable.\n'
      '  · Purely logistical or unremarkable turns: 0.\n'
      '  Only $userName\'s actions move this number. If $charName is the one who lied, erred, or felt '
      'guilty, return 0.\n'
      '- "trust_reason": one brief in-character thought from $charName about why (e.g. "They kept their '
      'word." or "Nobody is this generous without wanting something."), or "none" if the delta is 0.\n';

  static String _emotionSection(String charName, List<String> allowedLabels) =>
      '- "emotion": $charName\'s dominant emotional state right now (one nuanced word).\n'
      '  Not generic — find the texture: wistful not sad, flustered not happy, prickly not angry. Filter '
      'it through who $charName is: a stoic in deep pain reads "guarded", not "devastated"; a harsh '
      'character genuinely touched reads "flustered" or "disarmed", not "loving".\n'
      '${allowedLabels.isNotEmpty ? '  ${emotionLabelConstraint(allowedLabels)}\n' : ''}'
      '- "emotion_intensity": mild, moderate, or strong.\n';

  static String _arousalSection(
    String charName,
    String userName,
    int currentArousal,
    int refractoryTurnsLeft,
  ) =>
      '- "arousal_delta": physical desire shift this turn ($kMinArousalDelta to +$kMaxArousalDelta). '
      'Current arousal: $currentArousal/100.\n'
      '  Desire is as subjective as everything else — it rises only if what happened would genuinely stir '
      '$charName, given their tastes, appetites, and how they feel about $userName right now. The same '
      'kiss can be +15 for a smitten character, +3 for a shy conflicted one, 0 for an indifferent one, and '
      'negative for one who feels intruded on.\n'
      '  Wanted intimacy: +3 (a charged look, a whispered word) up to +25 (explicit contact $charName '
      'craves). Unwanted or badly-timed advances: 0 to -10 (and let the bond/trust fields carry the '
      'violation). Rejection or humiliation: -15 to -25.\n'
      '  Arousal measures DESIRE and PHYSICAL RESPONSE, not progress toward climax — climax only happens '
      'during active sexual contact at high arousal. At 60+ it is VISIBLE in $charName\'s behavior: '
      'breathing, focus, flushed skin, body language.\n'
      '  A non-sexual, non-romantic turn (food, work, errands, small talk, plain comfort) is 0 — and if '
      'current arousal is above 0 on such a turn, return roughly -5 to -10 so it cools back toward neutral.\n'
      '${refractoryTurnsLeft > 0 ? '  NOTE: $charName just climaxed and is in the post-orgasm refractory '
                '($refractoryTurnsLeft turns left). Their low desire right now is contented satedness, NOT '
                'aversion — an affectionate afterglow. Score gentle deltas (-3 to +5); a soft "not yet" to '
                'another advance is normal recovery, not a rejection, so do not score it negative unless '
                'something genuinely upsetting happened.\n' : ''}';

  // (There is no posture section here any more. Posture left the fused
  // one-shot call on 2026-08-08 along with the four-call path's copy: it is a
  // POST-generation question now — "where did this reply leave her" — and its
  // one remaining prompt lives with the pass that asks it, in
  // TimeService.evaluateTimeProgressAndPostureIfNeeded. Keeping a second
  // rubric here would have been a rubric nobody fires.)

  // Scene-time fields ride the fused one-shot call (strict one-shot vs
  // normal parity — the dedicated per-turn scene-time eval asks the same).
  static String _sceneTimeSection({bool plannerToday = false}) =>
      '- "minutes_elapsed": in-story minutes the LATEST exchange took (integer, 0-180). Most conversational '
      'exchanges take 2-15 minutes; activities (a meal, a walk, a task, travel) take longer. Use 0 ONLY '
      'when the scene is a continuous instant (mid-action, mid-sentence).\n'
      '- "new_day": true ONLY if the conversation explicitly transitioned to the next day (slept, woke up, '
      'scene break). false otherwise.\n'
      '${plannerToday ? '- "today_sentence": one sentence of what they are doing or planning today. '
                'Empty or "none" abandons the current hold. Omit to keep it.\n' : ''}';

  /// The ambitions a proposal should be steering toward, numbered with their
  /// stage words. Empty when the character has none — and then the whole
  /// forward-direction block, `serves_ambition` included, is omitted rather
  /// than sent as an empty list. A cardless character must cost exactly the
  /// tokens it did before ambitions existed.
  static String _ambitionRoster(List<({String text, int progress})> ambitions) {
    final open = openAmbitions(ambitions);
    if (open.isEmpty) return '';
    return 'Long-term ambitions (the mountain; each objective should be one switchback on it):\n'
        '${[for (var i = 0; i < open.length; i++) '${i + 1}. ${open[i].text} (${AmbitionService.stageWord(open[i].progress)})'].join('\n')}\n\n';
  }

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
  /// "ambition 2", or "2 — open her own bakery" all resolve the same way.
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

  /// The ambition-steering half of the objective instruction. Ambitions drive
  /// objectives, not the other way around (maintainer ruling 2026-08-07): the
  /// proposal is asked for the next believable step up one of the mountains
  /// above, favouring the least-advanced. Situational quests stay legal on
  /// purpose — a character whose every want serves the arc reads like a
  /// questgiver, not a person.
  static String _ambitionSteer(String charName, bool hasAmbitions) =>
      hasAmbitions
      ? '  PREFER a concrete next step toward one of the ambitions listed above — the one that is least '
            'far along and most relevant to what just happened. A goal that serves no ambition is still '
            'allowed when life genuinely pulls $charName that way, but when both fit, the ambition-serving '
            'one is the better answer.\n'
      : '';

  static String _servesAmbitionField(bool hasAmbitions) => hasAmbitions
      ? '- "serves_ambition": the NUMBER of the ambition the proposed objective is a step toward, or "none" '
            'if it serves none of them. Always "none" when "proposed_objective" is "none". Do not stretch — '
            'a quest that merely happens near an ambition does not serve it.\n'
      : '';

  static String _objectiveSection(
    String charName,
    String userName,
    String? primaryObjective,
    List<({String text, int progress})> ambitions,
  ) {
    final hasAmbitions = _ambitionRoster(ambitions).isNotEmpty;
    final body = primaryObjective != null
        ? '- "proposed_objective": a meaningful, emotionally-driven goal $charName independently wants to '
              'pursue — DISTINCT from their current main quest ("$primaryObjective"), true to who they are, '
              'and triggered by a STRONG, specific event THIS turn. Not a trivial step, and not a restatement '
              'of the main quest.\n'
              '  Default to "none" — the overwhelming majority of turns produce "none". Only propose one if '
              '$charName would genuinely lose sleep over it.\n'
        : '- "proposed_objective": an OVERARCHING goal $charName independently wants to pursue — a driving '
              'want big enough to span many scenes, born from who they are (their ambitions, wounds, '
              'appetites), e.g. "get $userName to admit their greatest fear" or a personal ambition they\'ve '
              'been chasing — not a one-scene errand. It becomes $charName\'s main quest and will be broken '
              'into concrete steps. Triggered by a strong, specific event THIS turn.\n'
              '  Default to "none" — the overwhelming majority of turns produce "none". Only propose one if '
              '$charName would genuinely lose sleep over it.\n';
    return '$body${_ambitionSteer(charName, hasAmbitions)}${_servesAmbitionField(hasAmbitions)}';
  }

  static String _fixationSection(String charName) =>
      '- "fixation_topic": an intrusive thought $charName cannot stop returning to — it haunts them across '
      'scenes, in their own style (a proud character obsesses over a slight; a lonely one over a moment of '
      'kindness). Not a temporary reaction. Default: "none".\n'
      '  Something they are stated to be drawn to, or put off by, is fair game here when the scene keeps '
      'returning to it — a fixation growing out of a known taste is the most believable kind. It still has '
      'to have been earned by what actually happened, not proposed because the taste exists.\n';

  static String _reasonSection() =>
      '- "reason": one brief sentence naming the key relationship change this turn, or "none".\n';

  static String _recentBlock(String recent) =>
      'Recent conversation:\n$recent\n\n';

  static String _jsonInstruction(List<String> keys) =>
      'Respond with ONLY a flat JSON object containing ${keys.map((k) => '"$k"').join(', ')}. '
      'Do NOT use markdown code blocks — return raw JSON only.';

  /// Tools-mode closing section (the journal_prompt pattern: everything above
  /// the format instruction is byte-identical between transports, so the two
  /// paths can never drift in what the model is told).
  static String _toolInstruction(String toolName) =>
      'Report your evaluation by calling the $toolName tool with the fields '
      'described above. Use ONLY the tool — no plain-text reply.';

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
  /// is the "real person" rule and the roster is who she is trying to
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
    bool plannerToday = false,
  }) =>
      '${judgePrefix(charName: charName, userName: userName, dossier: dossier, standing: standing, preferences: preferences, ambitions: ambitions)}'
      'Score how this exchange truly landed for $charName across every '
      'dimension below. Evaluate ALL of the following at once:\n'
      '${_bondSection(charName, userName)}'
      '${_trustSection(charName, userName)}'
      '${_emotionSection(charName, allowedEmotionLabels)}'
      '${_sceneTimeSection(plannerToday: plannerToday)}'
      '${arousalEnabled ? _arousalSection(charName, userName, arousalLevel, refractoryTurnsLeft) : ''}'
      '${_objectiveSection(charName, userName, primaryObjective, ambitions)}'
      '${_fixationSection(charName)}'
      '${_reasonSection()}'
      '\n'
      '${_recentBlock(recent)}'
      '${toolsMode ? _toolInstruction('report_realism') : _jsonInstruction(['relationship_delta', 'bond_reason', 'trust_delta', 'trust_reason', 'emotion', 'emotion_intensity', 'minutes_elapsed', 'new_day', if (plannerToday) 'today_sentence', if (arousalEnabled) 'arousal_delta', 'proposed_objective', if (_ambitionRoster(ambitions).isNotEmpty) 'serves_ambition', 'fixation_topic', 'reason'])}';
}
