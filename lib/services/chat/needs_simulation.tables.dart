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

/// Stepped background prose per need, worst-first (index 0 = empty, 1 =
/// crisis, 2 = strong, 3 = moderate, 4 = mild; the bands are
/// [NeedsSimulation.needStepUpperBounds]). PRONOUN-FREE by design
/// (docs/design/prompt-state-injection.md §3): these lines render directly
/// inside the composed state block right after a header that names the
/// character ("Hunger: [line]"), so gendered or generic pronouns here would
/// clash with the named, gendered header on small models (the "their
/// stomach… she said" template-paste read). Keep any new lines pronoun-free
/// participial/nominal phrases for the same reason. ({{user}} macros are
/// fine — the block is macro-resolved.) The mild line always says it is not
/// pressing, so a small model does not escalate it. Bladder lines say "a
/// bathroom" and leave the rest to the model, the Sims way.
const Map<String, List<String>> _needSteppedText = {
  'hunger': [
    '''Starving to the point of collapse: grey-faced, vision swimming, knees going. A real physical crisis, not a mood.''',
    '''Ravenous and shaky: light-headed, hands unsteady, thoughts pulled back to food every few moments; eating has become the priority.''',
    '''Properly hungry: a hollow, gnawing stomach that is hard to ignore; a little short-tempered and distracted, actively looking for a chance to eat.''',
    '''Getting hungry: the stomach starting to feel empty; a meal within the hour would be good, and may say so or suggest food if it fits.''',
    '''Could eat. A passing thought of food, nothing pressing; easily set aside.''',
  ],
  'bladder': [
    '''Control gives out: an accident, right now, in the scene. Hot, unstoppable, and the shame is immediate.''',
    '''Desperate for a bathroom: fighting to hold on, thighs pressed together, voice tight; minutes matter and an accident is close.''',
    '''Needs a bathroom soon: a strong, insistent pressure that makes it hard to settle; shifting in place and looking for any excuse to go.''',
    '''Needs a bathroom before too long: a steady, noticeable pressure; keeping an eye out for a natural moment to slip away.''',
    '''Could use a bathroom at some point. A faint awareness, nothing pressing; no need to act on it yet.''',
  ],
  'energy': [
    '''Collapsing from exhaustion: the body simply gives out, eyes fluttering closed, slumping to the floor or into {{user}}'s arms.''',
    '''Fighting to stay awake: head nodding, words slow and thick, eyes drifting shut mid-sentence; sleep could take over any moment.''',
    '''Worn out: heavy limbs, slow thoughts, every task taking effort; openly wanting to lie down and likely to say so.''',
    '''Tired: movements a touch slower, less animated than usual; a yawn may slip out, and a rest or an early night sounds good.''',
    '''A little tired. Could do with sitting down for a bit; nothing that changes the moment.''',
  ],
  'social': [
    '''Overwhelmed by loneliness: on the edge of breaking down; any real warmth will be clung to.''',
    '''Painfully isolated: hollow and raw, close to breaking down without some genuine connection soon.''',
    '''Lonely: the lack of real connection is starting to hurt; quieter, clingier or more fragile than usual, reaching for meaningful moments.''',
    '''Missing real connection: a little keener than usual for conversation or closeness, and inclined to draw it out.''',
    '''A small wish for company. A touch warmer and more attentive than usual; nothing more.''',
  ],
  'fun': [
    '''Climbing the walls: unable to sit still another minute; will act out, unwisely, for any kind of stimulation.''',
    '''Bored to the point of recklessness: dangerously restless, liable to do something rash or inappropriate just to feel something.''',
    '''Thoroughly bored: restless and fidgeting, ready to suggest almost anything to break the monotony.''',
    '''Getting bored: the current situation feels flat; fidgety, and hoping for a change of pace.''',
    '''A little under-stimulated. Open to something fun or different if it comes up; not bothered otherwise.''',
  ],
  'hygiene': [
    '''Filthy: the grime or smell strong enough to be distressing; acutely self-conscious, and it stays until a wash.''',
    '''Genuinely grimy and very aware of it: an urge to cover up or pull away from contact until there is a chance to clean up.''',
    '''Noticeably dirty and self-conscious about it: thoughts keep returning to a wash or a change of clothes; may hold back from close contact.''',
    '''Starting to feel unkempt: a quiet discomfort, and a wish to freshen up when there is a chance.''',
    '''A little grubby. Faintly aware of it, not bothered.''',
  ],
  'comfort': [
    '''Unbearable: impossible to stay like this a moment longer; relief will be sought whatever it disrupts.''',
    '''In real physical distress: too hot, too cold, cramped or aching badly; focus on anything else is a struggle.''',
    '''Clearly uncomfortable: constantly adjusting position or surroundings, unable to settle, and looking to fix whatever is causing it.''',
    '''Uncomfortable: a persistent irritation, whether temperature, pressure or stiffness, that makes it hard to fully relax; may shift position or mention it.''',
    '''Slightly uncomfortable. A minor physical irritation (a stiff neck, a warm room), easily ignored.''',
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
  '''Stripped of every trace of natural scent: raw, exposed and unsettled; nothing feels right until it returns. (About missing a natural body scent, never about seeking out filth.)''',
  '''Scrubbed and scentless in a way that feels wrong on the skin: exposed and on edge without the familiar scent. (About missing a natural body scent, never about seeking out filth.)''',
  '''Uncomfortably fresh: too soft, too soapy; that thorough wash already regretted and the natural musk wished back.''',
  '''A little too clean: the familiar natural scent is thin, and its absence is quietly missed.''',
  '''A faint just-washed freshness. A touch too clean for comfort; barely registers.''',
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
