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
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';

/// The shared judgment fragments [RealismPromptBuilder] composes into every
/// judge prompt. Pure statics, no state.
class RealismPromptFragments {
  RealismPromptFragments._();

  /// Sentence-boundary-aware trim so capped card text never ends (or starts)
  /// mid-thought. [fromEnd] keeps the tail (used for growth, where the latest
  /// entries matter most).
  static String trimTo(String text, int limit, {bool fromEnd = false}) {
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

  static String subjectivityFrame(
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

  /// PR 7 (bonding surge): the ONE conditional the afterglow windows speak
  /// with — the hard and soft refractory notes, the warmth-tail note, and
  /// the bond section — so the copy cannot drift between them. Conditioned
  /// on WANTED intimacy plus existing warmth, never on orgasm itself: the
  /// duty / dissociation archetype must have a legal reading, and the duty
  /// branch names the honest score (review M2 — a hedged "may not" under
  /// two unconditional warmth sentences reads as permission to climb).
  /// The notes only carry it when the SAME prompt scores bond
  /// ([arousalSection] `bondScoredHere`): dangling bond advice on the
  /// multi-call emotional judge — whose only lever is `arousal_delta`,
  /// capped gentle by the very note — hands small models a number to
  /// inflate (review M1). The trio lane gets the conditional from
  /// [bondSection] on the relationship judge instead, where the field is.
  /// Prompt-only — existing bands and authored tastes are the levers; no
  /// state, no new fields, no scoring code.
  static String bondSurgeClause(String charName, String userName) =>
      'If the climax was wanted and $charName holds real warmth toward '
      '$userName, affectionate contact during the afterglow counts more '
      'toward short-term bond; if it was duty, transaction, or skill on '
      'autopilot, the body cools on schedule and the heart may not follow '
      '— a flat or dipped bond is the honest score there';

  static String bondSection(String charName, String userName) =>
      '- "relationship_delta": how this exchange shifted $charName\'s genuine warmth toward $userName '
      '($kMinRelationshipDelta to +$kMaxRelationshipDelta).\n'
      '  Positive = it drew $charName closer by THEIR standards. Negative = it pushed them away — which '
      'includes well-meant gestures that trample their boundaries, pride, or pace, not only rudeness or cruelty.\n'
      '  Magnitude = how deeply the moment lands for $charName: ±1-2 barely registers | ±3-5 clearly felt | '
      '±6-9 strongly felt, stays with them | ±10-15 rare, relationship-redefining.\n'
      '  Most ordinary exchanges land between -2 and +2. 0 is the honest score when the turn simply '
      'didn\'t move $charName either way.\n'
      '  ${bondSurgeClause(charName, userName)}.\n'
      '- "bond_reason": one brief in-character thought from $charName explaining the shift '
      '(e.g. "They actually listened." or "Too much, too fast."), or "none" if the delta is 0.\n';

  static String trustSection(String charName, String userName) =>
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

  static String emotionSection(
    String charName,
    List<String> allowedLabels, {
    String userName = 'them',
    bool pcdActive = false,
  }) =>
      '- "emotion": $charName\'s dominant emotional state right now (one nuanced word).\n'
      '  Not generic — find the texture: wistful not sad, flustered not happy, prickly not angry. Filter '
      'it through who $charName is: a stoic in deep pain reads "guarded", not "devastated"; a harsh '
      'character genuinely touched reads "flustered" or "disarmed", not "loving".\n'
      '${allowedLabels.isNotEmpty ? '  ${RealismPromptBuilder.emotionLabelConstraint(allowedLabels)}\n' : ''}'
      '- "emotion_intensity": mild, moderate, or strong.\n'
      '- "emotion_cause": why $charName feels this, in at most twelve words, in '
      '$charName\'s own terms — never a quote of the other person. "none" when '
      'neutral.\n'
      '- "emotion_change": "held" if this is the mood going in, carrying on; '
      '"stoked" if it is the same feeling but this turn fed it afresh; "moved" '
      'if $charName feels something else now. A feeling that holds eases on '
      'its own; do not name it stronger just to keep it.\n'
      '${pcdActive ? '  NOTE: just after the peak, $charName may drift grey — "wistful" or '
                '"tearful" is an honest read right now, cause: something unnameable '
                'after the peak, NOT a reaction to $userName. The drift is weather, '
                'not judgment: bond and trust stay exactly as they were.\n' : ''}';

  static String arousalSection(
    String charName,
    String userName,
    int currentArousal,
    int refractoryMinutesLeft,
    bool clockRunning, {
    bool refractorySoft = false,

    /// PR 4: minutes owed on the warmth tail (frozen or live). Nonzero with
    /// `refractoryMinutesLeft == 0` puts the hold-not-raise note on the
    /// arousal section — the same "gentle band" job the refractory note
    /// does, one rung-late.
    int warmthTailMinutes = 0,

    /// PR 5: the opening turn of a beat whose climax verdict said {{user}}
    /// came too. Adds one shared-wind-down sentence to the refractory note
    /// — opening turn only, never a standing state.
    bool mutualOpening = false,

    /// PR 7 (review M1): the surge clause joins the notes only when THIS
    /// prompt also scores bond. The multi-call emotional judge has no
    /// bond field — advice with no field flows into arousal_delta, the
    /// number the note caps.
    bool bondScoredHere = false,
  }) =>
      '- "arousal_delta": physical desire shift this turn ($kMinArousalDelta to +$kMaxArousalDelta). '
      'Current arousal: $currentArousal/100.\n'
      '  Desire is as subjective as everything else — it rises only if what happened would genuinely stir '
      '$charName, given their tastes, appetites, and how they feel about $userName right now. The same '
      'kiss can be +15 for a smitten character, +3 for a shy conflicted one, 0 for an indifferent one, and '
      'negative for one who feels intruded on.\n'
      '  Wanted intimacy: +3 (a charged look, a whispered word) up to +25 (explicit contact $charName '
      'craves). Unwanted or badly-timed advances: 0 to -10 (and let the bond/trust fields carry the '
      'violation). Rejection or humiliation: -15 to -25.\n'
      '  These bands are the default. Authored "drawn to" / "warms to" tastes outrank the '
      'Rejection band: a matching turn is wanted intimacy, not humiliation. A genuine '
      'out-of-play stop is still Rejection.\n'
      '  Arousal measures DESIRE and PHYSICAL RESPONSE, not progress toward climax — climax only happens '
      'during active sexual contact at high arousal. At 60+ it is VISIBLE in $charName\'s behavior: '
      'breathing, focus, flushed skin, body language.\n'
      '  A non-sexual, non-romantic turn (food, work, errands, small talk, plain comfort) is 0 — and if '
      'current arousal is above 0 on such a turn, return roughly -5 to -10 so it cools back toward neutral.\n'
      '- "arousal_reason": one brief in-character thought from $charName explaining the desire shift '
      '(e.g. "The way they said my name." or "Not now, not like this."), or "none" if the delta is 0.\n'
      '${refractoryMinutesLeft > 0
          ? _refractoryNote(charName, userName, refractoryMinutesLeft, clockRunning, refractorySoft, mutualOpening: mutualOpening, surge: bondScoredHere)
          : warmthTailMinutes > 0
          ? _warmthTailNote(charName, userName, surge: bondScoredHere)
          : ''}';

  /// The warmth tail note (PR 4): the lock/window ended but the seeded
  /// warmth is owed. Its law is HOLD, never raise: a non-romantic turn
  /// above +10 returns 0 instead of the -5…-10 cool above — the curve
  /// fades, it does not fall. Since PR 7 it also carries the shared bond
  /// surge conditional (one clause, every window — see [bondSurgeClause]);
  /// the scoring law itself is still arousal only.
  static String _warmthTailNote(
    String charName,
    String userName, {
    bool surge = false,
  }) =>
      '  NOTE: $charName is still riding a warm afterglow after climax. '
      'Small kindnesses land a little deeper than usual today, and desire '
      'that has come back cools slowly: on a non-romantic turn with '
      'arousal above 10, HOLD arousal where it is (return 0) instead of '
      'cooling it toward neutral, and do not raise it on your own.'
      '${surge ? ' ${bondSurgeClause(charName, userName)}.' : ''}\n';

  /// The per-mode refractory note on the arousal section (PR 3). The hard
  /// note no longer says "just climaxed" — it rides every turn of a lock
  /// that can run three hours, and "just" read wrong late in one. Both
  /// modes keep the same gentle -3…+5 scoring band.
  static String _refractoryNote(
    String charName,
    String userName,
    int minutesLeft,
    bool clockRunning,
    bool soft, {
    bool mutualOpening = false,
    bool surge = false,
  }) {
    final left = describeRefractory(
      minutesLeft,
      clockRunning: clockRunning,
      soft: soft,
    ).prompt;
    // PR 5: one sentence, opening turn only — the shared wind-down colors
    // how low desire reads, never the scoring band.
    final shared = mutualOpening
        ? ' $charName and $userName came undone together, so the quiet '
              'after is shared recovery, not distance.'
        : '';
    // PR 7: the surge joins when this prompt scores bond (same clause,
    // one copy — [bondSurgeClause]'s doc owns the lane law).
    final surgeText = surge ? ' ${bondSurgeClause(charName, userName)}.' : '';
    return soft
        ? '  NOTE: $charName is oversensitive after climax $left but '
              'desire stays up; touch may read as too much — tenderness, '
              'not rejection. Score gentle deltas (-3 to +5); an advance '
              'that needs slowing down is a flinch, not a no.$shared$surgeText\n'
        : '  NOTE: $charName is in the post-orgasm refractory $left. '
              'Their low desire right now is contented satedness, NOT '
              'aversion — an affectionate afterglow. Score gentle deltas '
              '(-3 to +5); a soft "not yet" to another advance is normal '
              'recovery, not a rejection, so do not score it negative '
              'unless something genuinely upsetting happened.$shared$surgeText\n';
  }

  // (There is no posture section here any more. Posture left the fused
  // one-shot call on 2026-08-08 along with the four-call path's copy: it is a
  // POST-generation question now — "where did this reply leave them" — and its
  // one remaining prompt lives with the pass that asks it, in
  // TimeService.evaluateTimeProgressAndPostureIfNeeded. Keeping a second
  // rubric here would have been a rubric nobody fires.)

  /// The ambitions a proposal should be steering toward, numbered with their
  /// stage words. Empty when the character has none — and then the whole
  /// forward-direction block, `serves_ambition` included, is omitted rather
  /// than sent as an empty list. A cardless character must cost exactly the
  /// tokens it did before ambitions existed.
  static String ambitionRoster(List<({String text, int progress})> ambitions) {
    final open = RealismPromptBuilder.openAmbitions(ambitions);
    if (open.isEmpty) return '';
    return 'Long-term ambitions (the mountain; each objective should be one switchback on it):\n'
        '${[for (var i = 0; i < open.length; i++) '${i + 1}. ${open[i].text} (${AmbitionService.stageWord(open[i].progress)})'].join('\n')}\n\n';
  }

  /// The ambition-steering half of the objective instruction. Ambitions drive
  /// objectives, not the other way around (maintainer ruling 2026-08-07): the
  /// proposal is asked for the next believable step up one of the mountains
  /// above, favouring the least-advanced. Situational quests stay legal on
  /// purpose — a character whose every want serves the arc reads like a
  /// questgiver, not a person.
  static String ambitionSteer(String charName, bool hasAmbitions) =>
      hasAmbitions
      ? '  PREFER a concrete next step toward one of the ambitions listed above — the one that is least '
            'far along and most relevant to what just happened. A goal that serves no ambition is still '
            'allowed when life genuinely pulls $charName that way, but when both fit, the ambition-serving '
            'one is the better answer.\n'
      : '';

  static String servesAmbitionField(bool hasAmbitions) => hasAmbitions
      ? '- "serves_ambition": the NUMBER of the ambition the proposed objective is a step toward, or "none" '
            'if it serves none of them. Always "none" when "proposed_objective" is "none". Do not stretch — '
            'a quest that merely happens near an ambition does not serve it.\n'
      : '';

  static String objectiveSection(
    String charName,
    String userName,
    String? primaryObjective,
    List<({String text, int progress})> ambitions, {
    List<String> openGoals = const [],
    List<String> recentEnded = const [],
  }) {
    final hasAmbitions = ambitionRoster(ambitions).isNotEmpty;
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
    return '$body${knownGoals(openGoals, recentEnded)}${ambitionSteer(charName, hasAmbitions)}${servesAmbitionField(hasAmbitions)}';
  }

  /// What the character already wants and has lately finished or let go
  /// (objectives-that-keep-up.md part 3), so a proposal is a new want and
  /// not a rewording. Empty when there is nothing to list.
  static String knownGoals(List<String> openGoals, List<String> recentEnded) {
    if (openGoals.isEmpty && recentEnded.isEmpty) return '';
    final sb = StringBuffer();
    if (openGoals.isNotEmpty) {
      sb.write(
        '  Already wants: ${openGoals.map((g) => '"$g"').join('; ')}.\n',
      );
    }
    if (recentEnded.isNotEmpty) {
      sb.write('  Lately ${recentEnded.join('; ')}.\n');
    }
    sb.write(
      '  Propose only a want that is NOT one of these and not a rewording of '
      'one; otherwise "none".\n',
    );
    return sb.toString();
  }

  static String fixationSection(String charName) =>
      '- "fixation_topic": an intrusive thought $charName cannot stop returning to — it haunts them across '
      'scenes, in their own style (a proud character obsesses over a slight; a lonely one over a moment of '
      'kindness). Not a temporary reaction. Default: "none".\n'
      '  Something they are stated to be drawn to, or put off by, is fair game here when the scene keeps '
      'returning to it — a fixation growing out of a known taste is the most believable kind. It still has '
      'to have been earned by what actually happened, not proposed because the taste exists.\n';

  static String reasonSection() =>
      '- "reason": one brief sentence naming the key relationship change this turn, or "none".\n';

  static String recentBlock(String recent) =>
      'Recent conversation:\n$recent\n\n';

  static String jsonInstruction(List<String> keys) =>
      'Respond with ONLY a flat JSON object containing ${keys.map((k) => '"$k"').join(', ')}. '
      'Do NOT use markdown code blocks — return raw JSON only.';

  /// Tools-mode closing section (the journal_prompt pattern: everything above
  /// the format instruction is byte-identical between transports, so the two
  /// paths can never drift in what the model is told).
  static String toolInstruction(String toolName) =>
      'Report your evaluation by calling the $toolName tool with the fields '
      'described above. Use ONLY the tool — no plain-text reply.';
}
