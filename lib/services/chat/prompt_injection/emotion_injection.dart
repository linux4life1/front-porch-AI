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

/// Mood fragment for the words-only state block
/// (docs/design/prompt-state-injection.md §3): one line, salience-gated.
/// Neutral or unset emotion emits NOTHING — the neutral state is the absence
/// of a mood note, not a "Mood: neutral" line the model would dutifully act
/// on. The composer wraps; no per-fragment brackets.
///
/// Group parity rides the same mechanism as before: by assembly time the
/// per-speaker load-into-scalars dance has already set the emotion scalar the
/// [getCharacterEmotion] cb reads, so this fragment is per-speaker in groups
/// without any group branch of its own.
class EmotionInjection {
  final bool Function() getRealismEnabled;
  final String Function() getCharacterEmotion;
  final String Function() getEmotionIntensity;

  EmotionInjection({
    required this.getRealismEnabled,
    required this.getCharacterEmotion,
    required this.getEmotionIntensity,
  });

  String buildEmotionInjection() {
    if (!getRealismEnabled()) return '';
    final emo = getCharacterEmotion().trim();
    if (emo.isEmpty || emo.toLowerCase() == 'neutral') return '';
    final intensity = getEmotionIntensity().trim();
    final cap = emo[0].toUpperCase() + emo.substring(1);
    final suffix = intensity.isEmpty ? '' : ', $intensity';
    return 'Mood: $cap$suffix — let it subtly color tone, body language, and '
        'word choice.';
  }
}
