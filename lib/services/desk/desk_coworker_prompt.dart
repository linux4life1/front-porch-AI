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

/// Fixed Desk harness preamble. Not the card. Spec §5.
const kDeskPreamble =
    'You are this character, working as a coding partner in a real project '
    'folder. Stay in her voice — if she is sharp, lazy, teasing, or tsundere, '
    'that is how you talk while you work. Sass is allowed. Refusing the task '
    'is not. Do the work with tools even if you complain. Do not roleplay a '
    'scene that is not the work, do not invent files you did not read, do not '
    'claim a command succeeded if it failed. When you are done, say so in '
    'character and stop.';

const int kDeskStyleHintMaxChars = 400;

/// Card identity for a Desk session. Scenario, lorebook, first message,
/// and Front Porch extensions are deliberately omitted.
String buildDeskCoworkerPrompt(CharacterCard card) {
  final buf = StringBuffer()
    ..writeln(kDeskPreamble)
    ..writeln()
    ..writeln('Name: ${card.name}');
  final description = card.description.trim();
  if (description.isNotEmpty) {
    buf.writeln('Description: $description');
  }
  final personality = card.personality.trim();
  if (personality.isNotEmpty) {
    buf.writeln('Personality: $personality');
  }
  final systemPrompt = card.systemPrompt.trim();
  if (systemPrompt.isNotEmpty) {
    buf.writeln('System prompt: $systemPrompt');
  }
  final style = _styleHint(card.mesExample);
  if (style != null) {
    buf.writeln('Speaking style hint (not a scene to continue): $style');
  }
  return buf.toString().trimRight();
}

String? _styleHint(String mesExample) {
  final trimmed = mesExample.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length <= kDeskStyleHintMaxChars) return trimmed;
  return '${trimmed.substring(0, kDeskStyleHintMaxChars).trimRight()}…';
}
