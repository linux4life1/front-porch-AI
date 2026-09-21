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

part of 'realism_prompt_builder.dart';

/// Sentence-boundary-aware trim so capped card text never ends (or starts)
/// mid-thought. [fromEnd] keeps the tail (used for growth, where the latest
/// entries matter most).
String _trimTo(String text, int limit, {bool fromEnd = false}) {
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

String _subjectivityFrame(
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

String _bondSection(String charName, String userName) =>
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

String _trustSection(String charName, String userName) =>
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

String _emotionSection(String charName, List<String> allowedLabels) =>
    '- "emotion": $charName\'s dominant emotional state right now (one nuanced word).\n'
    '  Not generic — find the texture: wistful not sad, flustered not happy, prickly not angry. Filter '
    'it through who $charName is: a stoic in deep pain reads "guarded", not "devastated"; a harsh '
    'character genuinely touched reads "flustered" or "disarmed", not "loving".\n'
    '${allowedLabels.isNotEmpty ? '  ${RealismPromptBuilder.emotionLabelConstraint(allowedLabels)}\n' : ''}'
    '- "emotion_intensity": mild, moderate, or strong.\n';

String _arousalSection(
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
    '  These bands are the default. Authored "drawn to" / "warms to" tastes outrank the '
    'Rejection band: a matching turn is wanted intimacy, not humiliation. A genuine '
    'out-of-play stop is still Rejection.\n'
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
// POST-generation question now — "where did this reply leave them" — and its
// one remaining prompt lives with the pass that asks it, in
// TimeService.evaluateTimeProgressAndPostureIfNeeded. Keeping a second
// rubric here would have been a rubric nobody fires.)

/// The ambitions a proposal should be steering toward, numbered with their
/// stage words. Empty when the character has none — and then the whole
/// forward-direction block, `serves_ambition` included, is omitted rather
/// than sent as an empty list. A cardless character must cost exactly the
/// tokens it did before ambitions existed.
String _ambitionRoster(List<({String text, int progress})> ambitions) {
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
String _ambitionSteer(String charName, bool hasAmbitions) => hasAmbitions
    ? '  PREFER a concrete next step toward one of the ambitions listed above — the one that is least '
          'far along and most relevant to what just happened. A goal that serves no ambition is still '
          'allowed when life genuinely pulls $charName that way, but when both fit, the ambition-serving '
          'one is the better answer.\n'
    : '';

String _servesAmbitionField(bool hasAmbitions) => hasAmbitions
    ? '- "serves_ambition": the NUMBER of the ambition the proposed objective is a step toward, or "none" '
          'if it serves none of them. Always "none" when "proposed_objective" is "none". Do not stretch — '
          'a quest that merely happens near an ambition does not serve it.\n'
    : '';

String _objectiveSection(
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

String _fixationSection(String charName) =>
    '- "fixation_topic": an intrusive thought $charName cannot stop returning to — it haunts them across '
    'scenes, in their own style (a proud character obsesses over a slight; a lonely one over a moment of '
    'kindness). Not a temporary reaction. Default: "none".\n'
    '  Something they are stated to be drawn to, or put off by, is fair game here when the scene keeps '
    'returning to it — a fixation growing out of a known taste is the most believable kind. It still has '
    'to have been earned by what actually happened, not proposed because the taste exists.\n';

String _reasonSection() =>
    '- "reason": one brief sentence naming the key relationship change this turn, or "none".\n';

String _recentBlock(String recent) => 'Recent conversation:\n$recent\n\n';

String _jsonInstruction(List<String> keys) =>
    'Respond with ONLY a flat JSON object containing ${keys.map((k) => '"$k"').join(', ')}. '
    'Do NOT use markdown code blocks — return raw JSON only.';

/// Tools-mode closing section (the journal_prompt pattern: everything above
/// the format instruction is byte-identical between transports, so the two
/// paths can never drift in what the model is told).
String _toolInstruction(String toolName) =>
    'Report your evaluation by calling the $toolName tool with the fields '
    'described above. Use ONLY the tool — no plain-text reply.';
