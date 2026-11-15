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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/narrative_voice.dart';
import 'package:front_porch_ai/services/character_gen/creator_inputs_stamp.dart';

/// The Review step's portrait prompt for a saved card.
///
/// The desktop builds it from the live creator state (`CreatorState.
/// buildPortraitPromptSeed`, creator_state_engine.dart:319): the LLM's image
/// prompt with the character's name stripped, else a visual-tag fallback. The
/// web wizard reloads between steps, so the state is gone; the same facts ride
/// on the card's `creator_inputs` stamp (written by the web's create) and its
/// narrative-voice stamp. A card from before those keys falls back to the
/// card's own description, which is what the desktop fallback's last line
/// uses.
String buildPortraitPromptSeed(CharacterCard card) {
  final portrait = readCreatorPortraitInputs(card);
  final artStyle = portrait.artStyle.isEmpty ? 'Anime' : portrait.artStyle;
  final name = card.name.trim();
  final llmPrompt = portrait.imagePrompt;
  if (llmPrompt.isNotEmpty) {
    // Strip the character name out of the LLM-authored prompt, exactly as the
    // desktop does, so the image model doesn't render it as text.
    String clean = llmPrompt;
    if (name.isNotEmpty) {
      clean = clean
          .replaceAll(RegExp(RegExp.escape(name), caseSensitive: false), '')
          .trim();
      for (final part in name.split(RegExp(r'\s+'))) {
        if (part.length > 2) {
          clean = clean
              .replaceAll(
                RegExp('\\b${RegExp.escape(part)}\\b', caseSensitive: false),
                '',
              )
              .trim();
        }
      }
      clean = clean
          .replaceAll(RegExp(r',\s*,'), ',')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      if (clean.startsWith(',')) clean = clean.substring(1).trim();
    }
    return '$clean, $artStyle style';
  }

  // Fallback: assemble visual tags from whatever the card carries. The guided
  // appearance/hair/features/race fields are not stamped (they only exist in
  // the desktop session), so the description snippet closes the line, as the
  // desktop's own fallback does when it has few tags.
  final tags = <String>['character portrait', '$artStyle style'];
  final sex = portrait.sex.isNotEmpty
      ? portrait.sex
      : readNarrativeVoice(card).sex;
  if (sex.isNotEmpty) tags.add(sex.toLowerCase());
  if (portrait.age.isNotEmpty) tags.add('${portrait.age} years old');
  if (tags.length <= 4 && card.description.trim().isNotEmpty) {
    final snippet = card.description.trim();
    tags.add(snippet.length > 150 ? snippet.substring(0, 150) : snippet);
  }
  return tags.join(', ');
}
