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

part of 'needs_simulation.dart';

const List<String> _needKeys = [
  'hunger',
  'bladder',
  'energy',
  'social',
  'fun',
  'hygiene',
  'comfort',
];

const Map<String, int> _needDefaults = {
  'hunger': 75,
  'bladder': 80,
  'energy': 80,
  'social': 65,
  'fun': 65,
  'hygiene': 75,
  'comfort': 70,
};

const Map<String, int> _needDecay = {
  'hunger': 2,
  'bladder': 3,
  'energy': 3,
  'social': 2,
  'fun': 2,
  'hygiene': 1,
  'comfort': 2,
};

const Map<String, int> _needRestore = {
  'hunger': 50,
  'bladder': 70,
  'energy': 40,
  'social': 45,
  'fun': 40,
  'hygiene': 35,
  'comfort': 35,
};

/// Stepped background prose per need, worst-first (index 0 = crisis → 4 =
/// mild). PRONOUN-FREE by design (docs/design/prompt-state-injection.md §3):
/// these lines render directly inside the composed state block right after a
/// header that names the character ("Hunger: [line]"), so gendered or
/// generic pronouns here would clash with the named, gendered header on
/// small models (the "their stomach… she said" template-paste read). Keep
/// any new lines pronoun-free participial/nominal phrases for the same
/// reason. ({{user}} macros are fine — the block is macro-resolved.)
const Map<String, List<String>> _needSteppedText = {
  'hunger': [
    '''Doubled over by a violent stomach cramp — genuinely starving: vision swimming, knees weak, barely able to stay upright. The hunger has become a real physical crisis.''',
    '''Sharp, gnawing hunger cramps; light-headed and shaky, thoughts drifting uncontrollably to food, focus on anything else a real struggle.''',
    '''Stomach painfully hollow and tight — a constant, distracting ache; restless, short-tempered, thoughts keep returning to when the next meal might come.''',
    '''A steady, empty feeling in the stomach; thoughts occasionally wander toward food — a bit distracted and low-energy.''',
    '''A quiet, background emptiness in the stomach — not urgent, but noticeable; a chance to eat soon would be welcome.''',
  ],
  'bladder': [
    '''Control gives out completely — a sudden hot rush, an accident happening right now in the current scene; the humiliation is immediate and overwhelming.''',
    '''Fighting with everything not to lose control — thighs pressed tight, constant shifting, voice tight with strain; an accident is very close.''',
    '''A strong, insistent pressure has built up — visibly uncomfortable, watching for a polite way to slip away soon.''',
    '''A steady, distracting pressure low in the belly; the need keeps growing — a bathroom before too long would be a relief.''',
    '''A faint but persistent urge to use the restroom sits at the back of the mind, bringing slight restlessness.''',
  ],
  'energy': [
    '''The body gives out completely — eyes flutter mid-sentence and collapse follows, slumping to the floor or into {{user}}'s arms, fully unconscious from exhaustion.''',
    '''Barely staying awake — head nodding, speech slow and heavy, eyes unfocused; sleep could take over at any moment.''',
    '''A heavy, crushing tiredness; every movement takes effort and thoughts run slow — rest is desperately wanted.''',
    '''A deep weariness — movements a little slower, noticeably less animated than usual, clearly running low on energy.''',
    '''A comfortable, heavy tiredness behind the eyes; curling up to rest would be welcome if the chance arose.''',
  ],
  'social': [
    '''Overwhelming loneliness — hollow and raw, on the edge of breaking down without real, meaningful connection soon.''',
    '''Painfully isolated; the lack of real connection is starting to hurt — unusually quiet, clingy, or emotionally fragile.''',
    '''A deep ache for genuine connection sits in the chest; casual interaction feels hollow — meaningful moments and closeness keep being sought.''',
    '''Feeling the absence of real companionship — a little more eager than usual for meaningful conversation or physical closeness.''',
    '''A quiet, gentle craving for real connection — a touch warmer and more attentive than normal.''',
  ],
  'fun': [
    '''Torturous boredom — dangerously restless, liable to do something reckless or wildly inappropriate just to feel *something* again.''',
    '''Deeply restless and thoroughly bored — constant fidgeting, ready to suggest almost anything to break the monotony.''',
    '''A heavy restlessness has settled in; everything feels dull — any excuse for something more stimulating keeps being sought.''',
    '''Noticeably bored and fidgety; the current situation feels flat — actively hoping for a change of pace.''',
    '''A mild restlessness — a little more eager than usual for something fun or different to happen.''',
  ],
  'hygiene': [
    '''Filthy and overwhelmed by it — the grime or smell strong enough to cause physical discomfort and self-consciousness to the point of distress.''',
    '''Genuinely dirty and very aware of it — an urge to cover up or pull away from contact until there's a chance to clean up.''',
    '''A persistent grimy feeling clings — self-conscious, thoughts keep returning to washing or changing.''',
    '''Starting to feel noticeably unkempt — a quiet discomfort, wanting to freshen up soon.''',
    '''A faint background sense of being a little grubby — mildly self-conscious about it.''',
  ],
  'comfort': [
    '''Unbearable physical discomfort — impossible to stay like this any longer; relief will be sought no matter what it disrupts.''',
    '''The body is in real distress — too hot, too cold, cramped, or aching badly; constant shifting, focus on anything else a struggle.''',
    '''A strong physical discomfort wears on — constant adjusting of position or surroundings, clearly unable to settle.''',
    '''Noticeably uncomfortable — a persistent physical irritation (temperature, pressure, stiffness) making it hard to fully relax.''',
    '''A mild but persistent physical discomfort in the background, bringing slight restlessness.''',
  ],
};

/// Hygiene descriptions for a character with "enjoys low hygiene" set. For
/// them the whole scale is inverted: being DIRTY is comfort, being CLEAN is
/// the aversive state. The normal [needSteppedText] is all phrased "dirty =
/// bad", so reusing it after the step inversion would describe a freshly-
/// scrubbed character as "feeling filthy" — the exact opposite of the truth.
/// This list is worst-first like the others (index 0 = scrubbed unbearably
/// clean → index 4 = only faintly too fresh). This is an ODOR/MUSK preference
/// ONLY: the character is soothed by their own unwashed body scent and put off
/// by feeling soap-clean. It is NOT a drive to make a mess — no seeking dirt,
/// mud, or filth acts (a character once dumped a mop bucket over themselves off
/// the old wording). The distress is missing their natural scent; the comfort
/// is simply remaining unwashed and musky. Pronoun-free like
/// [needSteppedText] (rendered right after a named header).
const List<String> _hygieneSteppedTextWhenEnjoysLow = [
  '''Scrubbed and scentless in a way that feels wrong on the skin — the familiar musk scoured completely away; exposed and on edge, quietly wishing that natural scent were back. (This is about missing a natural body scent, never about seeking out filth.)''',
  '''Uncomfortably fresh — too soft, too soapy, the natural scent washed thin; its absence is off-putting, that thorough wash already regretted.''',
  '''Still a little too clean for comfort — without the familiar musk comes an odd self-consciousness, as if something comforting were missing.''',
  '''Starting to feel a touch over-scrubbed; the settled, lived-in comfort of an unwashed natural scent is quietly missed.''',
  '''A faint just-washed freshness lingers — mildly unsatisfying next to the natural musk.''',
];

// Mandatory "this just happened" events fired when a HARD-EVENT need bottoms
// out (≤0). Neutral voice (they/them). Each line carries its OWN observable
// evidence, so the injection wrapper stays generic (no bladder-centric list).
// Deliberately NO social/fun entries — moods, not discrete events.
// Hygiene still GETS a beat (they notice they reek, they hate it) but
// has no recovery floor — the meter stays at 0 until they actually wash.
// Enjoys-low-hygiene skips the beat (0 hygiene is comfort for them).
const Map<String, String> _needCatastropheText = {
  'hunger':
      '''Starvation buckles them — they sag, grey-faced and unsteady, and have to catch themselves on the nearest support just to stay upright. Their body has hit its limit and it shows.''',
  'bladder':
      '''Their control gives out. It's happening right now, in the scene — a hot, unstoppable release, fabric darkening, a spreading wet patch, the smell of it. The accident is occurring this instant, not a warning or a near-miss.''',
  'energy':
      '''Exhaustion drops them mid-action — their knees buckle and they collapse, briefly blacking out as they slump to the floor or the nearest surface. They come to a few seconds later, dazed and groggy, barely able to keep their eyes open or form a clear thought.''',
  'hygiene':
      '''They can smell themselves — grimy, sour, unmistakable — and it makes them self-conscious, uncomfortable, embarrassed. They do not drop what they are doing to go wash; the stink just sits on them.''',
  'comfort':
      '''The strain becomes unbearable — the cramped position, the temperature, the pressure, the restraint, whatever is causing it. They have to shift, break contact with the source, or otherwise ease it; they can't simply hold still through it any longer.''',
};

/// Recovery floor by need CLASS after a catastrophe (no magic per-need +N):
///   body-reset — a physiological event that (partly) empties the meter:
///     bladder (just went → nearly empty), hunger (stabilized, not fed),
///     energy (came to groggy, NOT a full rest — user said collapse-and-groggy,
///     not fall-asleep).
///   crisis-vent — a behavioral/sensory peak with only partial relief:
///     comfort (the moment passes; nothing was actually fixed).
/// Hygiene is deliberately ABSENT: noticing they reek does not clean them.
const Map<String, int> _needPostCatastropheFloor = {
  'bladder': 85,
  'hunger': 70,
  'energy': 65,
  'comfort': 60,
};

/// The only needs that fire a hard catastrophe (see [needCatastropheText]).
const List<String> _catastropheNeeds = [
  'bladder',
  'energy',
  'hunger',
  'comfort',
  'hygiene',
];

// Decay modifiers (non-buffer ones retained; afterglow_damp and
// suppression-conditioned ones removed or simplified).
final List<DecayModifier> _decayModifiers = <DecayModifier>[
  (
    name: 'low_energy_hunger_boost',
    condition: (key, vector, ctx) =>
        key == 'hunger' && (vector['energy'] ?? 50) <= 30,
    factor: (key, current, ctx) => 1.35,
  ),
  (
    name: 'low_energy_comfort_boost',
    condition: (key, vector, ctx) =>
        key == 'comfort' && (vector['energy'] ?? 50) <= 25,
    factor: (key, current, ctx) => 1.25,
  ),
  (
    name: 'low_fun_social_boost',
    condition: (key, vector, ctx) =>
        key == 'social' && (vector['fun'] ?? 50) <= 20,
    factor: (key, current, ctx) => 1.4,
  ),
  (
    name: 'low_bladder_comfort_boost',
    condition: (key, vector, ctx) =>
        key == 'comfort' && (vector['bladder'] ?? 50) <= 20,
    factor: (key, current, ctx) => 1.25,
  ),
  // (enjoys low hygiene arousal mutation and other buffer-dependent
  // modifiers removed with the buffers)
  // Living Time weather (living-time-features.md §3) — deliberately tiny.
  // Comfort: base 2 ×1.25 → rounds to 3/turn in rough weather.
  // Fun: base 2 ×0.5 → 1/turn on clear days (a plain ×0.75 would round back
  // to 2 and do nothing). Both vanish when weather is off (getWeather null).
  (
    name: 'weather_rough_comfort',
    condition: (key, vector, ctx) {
      if (key != 'comfort') return false;
      final w = ctx.getWeather?.call();
      if (w == null) return false;
      // Rank-based so extremes count too; identical for classic bands.
      return w.condition == WeatherCondition.storm ||
          w.condition == WeatherCondition.rain ||
          w.temp.rank >= TempBand.hot.rank ||
          w.temp.rank <= TempBand.cold.rank;
    },
    factor: (key, current, ctx) => 1.25,
  ),
  (
    name: 'weather_clear_fun',
    condition: (key, vector, ctx) =>
        key == 'fun' &&
        ctx.getWeather?.call()?.condition == WeatherCondition.clear,
    factor: (key, current, ctx) => 0.5,
  ),
];

/// How far ONE exchange may push a need DOWN, at strength 1x.
///
/// THE RULE: a described EVENT must visibly beat a standard turn's drift.
/// Maintainer, 2026-08-08: "I would like needs to be variable still. For
/// example drinking a soda would cause bladder to drop… more than on a
/// standard turn." Every number here is at least 2x — usually 3x — that
/// need's entry in [needDecay], so narrating something always outpaces
/// ambient decline. A first draft set bladder to 6, exactly its decay rate,
/// which would have made drinking a soda indistinguishable from nothing
/// happening. That is the flatness this table exists to avoid, and
/// needs_depletion_cap_test asserts the margin rather than trusting it.
///
/// PER-NEED, because a single number is either too tight for the needs whose
/// mechanism IS events or too loose for the ones decay already owns:
///   * bladder (decay 3) gets the widest bite. It is a fast clock AND the
///     need most obviously moved by a described act — drinking, a long
///     drive, holding it. 18 is several turns of normal build.
///   * hygiene (decay 1) barely drifts at all; sex, mud and rain are the
///     only things that move it, so it needs room despite the tiny decay.
///   * hunger, energy, comfort sit at 12 — a real cost, not a cliff.
///   * social and fun move most through RESTORATION (company, play), which
///     is unbounded, so their depletion bite is the smallest.
///
/// What this is NOT: a licence for the eval to drive the simulation. Decay
/// still owns the ambient slide, and the prompt now tells the eval to report
/// a negative ONLY for something the scene explicitly describes costing them.
/// These are the ceiling on a real event, not a per-turn expectation.
const Map<String, int> _sceneDepletionAt1x = {
  'hunger': 12,
  'bladder': 18,
  'energy': 12,
  'social': 10,
  'fun': 10,
  'hygiene': 15,
  'comfort': 12,
};
