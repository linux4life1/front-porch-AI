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

import 'package:flutter/painting.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/readable_dialogue_tint.dart';

import 'ui_settings.dart';

/// The dialogue and action tints for text drawn inside the user's own
/// bubble (quoted speech, `*actions*`, the sender name). One place decides
/// them so every reader agrees.
extension UserBubbleDialogue on UiSettings {
  Color userBubbleDialogueColorFor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    return userBubbleDialogueColor(
      dialogue: getDialogueColor(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
      bubble: getUserBubbleColor(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
      userText: getUserTextColor(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
      userChoseDialogue: _dialogueColorChosen(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
    );
  }

  /// `*Action*` text in the user's bubble: a shipped default that would not
  /// read on that bubble is tinted the same way as quoted speech.
  Color userBubbleActionColorFor(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final bool chosen;
    if (themePreset != null) {
      chosen = themeOverrides?.actionColor != null;
    } else {
      chosen =
          character?.frontPorchExtensions?.actionColor != null ||
          globalActionColorChosen;
    }
    return userBubbleDialogueColor(
      dialogue: getActionColor(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
      bubble: getUserBubbleColor(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
      userText: getUserTextColor(
        character,
        themePreset: themePreset,
        themeOverrides: themeOverrides,
      ),
      userChoseDialogue: chosen,
    );
  }

  /// Whether the colour [UiSettings.getDialogueColor] resolves to was picked
  /// by the user (theme override, per-character or global Chat Appearance)
  /// rather than a shipped default. Same resolution order as that getter.
  bool _dialogueColorChosen(
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    if (themePreset != null) return themeOverrides?.dialogueColor != null;
    if (character?.frontPorchExtensions?.dialogueColor != null) return true;
    return globalDialogueColorChosen;
  }
}
