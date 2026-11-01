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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/realism_colors.dart';
import 'mood_look.dart';

/// The frame a speaker's latest bubble wears at Mood on the character's
/// full level: a border and a glow in the message's own mood tone. The
/// tone comes from the stamp on the message (`emotion_label`), so regen,
/// swipe, Continue and edit re-derive it; the loudness comes from the
/// speaker's live intensity and hold while the stamp still matches the
/// live mood, else it paints mild. Null when there is nothing to wear.
typedef MoodBubbleFrame = ({Border border, List<BoxShadow> shadow});

MoodBubbleFrame? moodBubbleFrame({
  required ChatMessage message,
  required CharacterCard? character,
  required ChatService? chat,
  required MoodLook look,
}) {
  if (!look.bubblesOn || chat == null || message.isUser) return null;
  final label = (message.activeMetadata?['emotion_label'] as String?)
      ?.trim()
      .toLowerCase();
  if (label == null || label.isEmpty) return null;
  final live = chat.isGroupMode
      ? (character == null ? null : chat.getMoodForGroupCharacter(character))
      : MoodState(
          label: chat.characterEmotion,
          intensity: chat.emotionIntensity,
          held: chat.emotionHeldTurns,
        );
  final matches = live != null && live.label.trim().toLowerCase() == label;
  final mood = MoodAtmosphere.of(
    MoodState(
      label: label,
      intensity: matches ? live.intensity : 'mild',
      held: matches ? live.held : 0,
    ),
    drama: look.drama,
  );
  final tone = mood.tone;
  if (tone == null || !mood.isOn) return null;
  final hue = RealismColors.moodToneColor(tone);
  final a = mood.strength.clamp(0.0, 1.0);
  return (
    border: Border.all(
      color: hue.withValues(alpha: 0.45 + 0.5 * a),
      width: 1 + 2 * a,
    ),
    shadow: [
      BoxShadow(
        color: hue.withValues(alpha: 0.5 * a),
        blurRadius: 16 + 36 * a,
        spreadRadius: 1 + 5 * a,
      ),
    ],
  );
}
