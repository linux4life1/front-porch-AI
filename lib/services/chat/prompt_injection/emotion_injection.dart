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

import 'package:front_porch_ai/services/chat/mood_effects.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';

/// The mood fragment of the state block (docs/design/mood-with-bite.md):
/// one line that scales with intensity and names the cause, and at
/// moderate and strong a second line with the pull the feeling has, in the
/// character's own way. One fragment, one slot, so the block's order holds.
class EmotionInjection {
  final bool Function() getRealismEnabled;
  final String Function() getCharacterEmotion;
  final String Function() getEmotionIntensity;

  /// Cause and hold are optional so a host that has neither (older callers,
  /// tests) gets the plain mood line, cause-less and fresh.
  final String Function() getEmotionCause;
  final int Function() getEmotionHeldTurns;

  EmotionInjection({
    required this.getRealismEnabled,
    required this.getCharacterEmotion,
    required this.getEmotionIntensity,
    String Function()? getEmotionCause,
    int Function()? getEmotionHeldTurns,
  }) : getEmotionCause = getEmotionCause ?? _noCause,
       getEmotionHeldTurns = getEmotionHeldTurns ?? _noHold;

  static String _noCause() => '';
  static int _noHold() => 0;

  String buildEmotionInjection() {
    if (!getRealismEnabled()) return '';
    final mood = MoodState(
      label: getCharacterEmotion().trim(),
      intensity: getEmotionIntensity().trim(),
      cause: getEmotionCause(),
      held: getEmotionHeldTurns(),
    );
    if (mood.isNeutral) return '';
    final line = moodPromptLine(mood);
    final effects = moodEffectsLine(mood);
    return effects.isEmpty ? line : '$line\n$effects';
  }
}
