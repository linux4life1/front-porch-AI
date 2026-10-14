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

/// The words the model is handed for a mood (docs/design/mood-with-bite.md
/// "The voice in the prompt"): the mood line, which scales with intensity
/// and names the cause, and the effects line, the pull the feeling has on
/// what the character does, spoken only at moderate and strong, always as
/// an inclination in their own way and never as an instruction.
library;

import 'package:front_porch_ai/services/chat/mood_physics.dart';

/// The pull, by tone family, at moderate (first) and strong (second).
/// Describes inclinations. A character in any of these may still say no.
const Map<MoodTone, (String, String)> kMoodEffectsCopy = {
  MoodTone.sour: (
    'less patience, no warmth offered; a favour is a harder sell',
    'the grievance comes first: they may refuse, argue, withdraw or leave '
        'before anything else',
  ),
  MoodTone.low: (
    'little initiative, shorter replies, easily discouraged',
    'withdrawn: may not engage, answers in fragments, and nothing lands as '
        'good news',
  ),
  MoodTone.anxious: (
    'hedges, seeks reassurance, avoids commitments and risk',
    'fixed on the threat, cannot settle into the scene, may bolt or freeze',
  ),
  MoodTone.lifted: (
    'takes initiative, says yes more readily, playful',
    'carried away: bold, generous, starts things, laughs off small slights',
  ),
  MoodTone.warm: (
    'attentive, reaches out, small acts of care',
    'openly tender: closeness before anything else, quick to forgive',
  ),
  MoodTone.charged: (
    'leans in, pushes the scene toward what they want',
    'single-minded: everything bends toward it and patience is thin',
  ),
};

String _capitalised(String label) {
  final l = label.trim();
  if (l.isEmpty) return l;
  return l[0].toUpperCase() + l.substring(1);
}

/// `Mood: Furious, strong, because <cause>, still — it leads this reply: …`
/// The prefix `Mood: <Label>, <intensity>` is the one the prompt pins have
/// always checked. Empty for a neutral mood.
String moodPromptLine(MoodState mood) {
  if (mood.isNeutral) return '';
  final rank = mood.intensityRank;
  final intensity = moodIntensityWord(rank);
  final cause = cleanMoodCause(mood.cause);
  final hold = moodHoldWord(mood.held);
  final head = StringBuffer('Mood: ${_capitalised(mood.label)}');
  if (intensity.isNotEmpty) head.write(', $intensity');
  if (cause.isNotEmpty) {
    head.write(rank <= 1 ? ', since $cause' : ', because $cause');
  }
  if (hold.isNotEmpty) head.write(', $hold');
  final tail = switch (rank) {
    >= 3 => 'it leads this reply: they act on it before anything else.',
    2 => 'it shapes what they say and do this turn.',
    _ => 'it colours tone and word choice.',
  };
  return '$head — $tail';
}

/// `In their own way: <pull>.` at moderate and strong; empty at mild, for
/// neutral, and for a label whose family the map does not know.
String moodEffectsLine(MoodState mood) {
  if (mood.isNeutral) return '';
  final rank = mood.intensityRank;
  if (rank < 2) return '';
  final tone = moodToneOf(mood.label);
  if (tone == null) return '';
  final (moderate, strong) = kMoodEffectsCopy[tone]!;
  return 'In their own way: ${rank >= 3 ? strong : moderate}.';
}

/// The sidebar and phone row: `Furious (strong) · because he lied · still`.
String moodDisplayLine(MoodState mood) {
  if (mood.isNeutral) return 'Neutral';
  final parts = <String>[
    mood.intensity.trim().isEmpty
        ? _capitalised(mood.label)
        : '${_capitalised(mood.label)} (${mood.intensity.trim()})',
  ];
  final cause = cleanMoodCause(mood.cause);
  if (cause.isNotEmpty) parts.add('because $cause');
  final hold = moodHoldWord(mood.held);
  if (hold.isNotEmpty) parts.add(hold);
  return parts.join(' · ');
}
