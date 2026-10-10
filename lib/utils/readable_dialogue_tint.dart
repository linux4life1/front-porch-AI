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

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Lowest contrast (WCAG ratio) quoted speech may have against the user's
/// own bubble before it is re-tinted. 3:1 is the WCAG floor for text that
/// has to stay legible; the dialogue tint is medium weight.
const double kMinUserDialogueContrast = 3.0;

/// What a re-tint aims for when the bubble allows it (WCAG body text).
const double kTargetUserDialogueContrast = 4.5;

/// WCAG contrast ratio of two colours, 1 (same) to 21 (black on white).
/// Alpha is ignored: bubbles are judged as if drawn fully opaque.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The colour quoted speech is drawn in inside the user's own bubble.
///
/// A dialogue colour the user picked is always kept. Otherwise the default
/// tint is kept when it reads on [bubble]; when it does not (an orange quote
/// on a green bubble), it keeps its hue and is lightened or darkened toward
/// the side the user's own [userText] sits on: to the target contrast when
/// that side can reach it, else just past the floor.
/// Mirrored by `userBubbleDialogueColor` in `web_ui/src/chatColors.ts`.
Color userBubbleDialogueColor({
  required Color dialogue,
  required Color bubble,
  required Color userText,
  required bool userChoseDialogue,
}) {
  if (userChoseDialogue) return dialogue;
  if (contrastRatio(dialogue, bubble) >= kMinUserDialogueContrast) {
    return dialogue;
  }
  final lighten = userText.computeLuminance() >= bubble.computeLuminance();
  final hsl = HSLColor.fromColor(dialogue);
  const steps = 50;
  Color? floor;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final lightness = lighten
        ? hsl.lightness + (1 - hsl.lightness) * t
        : hsl.lightness * (1 - t);
    final tinted = hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();
    final ratio = contrastRatio(tinted, bubble);
    if (ratio >= kTargetUserDialogueContrast) return tinted;
    if (ratio >= kMinUserDialogueContrast) floor ??= tinted;
  }
  // Even white or black of that hue cannot reach the floor: the user's own
  // text colour is the one they already chose to read on this bubble.
  return floor ?? userText;
}
