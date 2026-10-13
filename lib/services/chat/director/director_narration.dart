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

import 'director_note.dart';

/// How many recent transcript lines the narrator reads.
const int kNarrationHistoryLines = 12;

/// The narrator's prompt: one short third-person beat that moves the scene
/// (setting, weather, a time skip, something happening) without speaking
/// for anyone. [hint] is what the director asked for, or empty.
String narrationPrompt({
  required List<String> recentLines,
  required List<String> castNames,
  required String hint,
}) {
  final ask = hint.trim().isEmpty
      ? 'Describe what happens next in the scene.'
      : 'The director asks for this: ${hint.trim()}';
  return 'You are the narrator of a roleplay scene. The characters are '
      '${castNames.join(', ')}.\n\n'
      'Recent scene:\n${recentLines.join('\n')}\n\n'
      '$ask\n\n'
      'Write ONE short narration beat of two to four sentences, in the third '
      'person and the present tense: the setting, the weather, the passing '
      'of time, or something that happens. Do NOT write any dialogue, and do '
      'NOT speak or decide for any character. Reply with the narration only, '
      'no label and no quotes.';
}

/// The narration as it lands in the transcript: a director-family line, so
/// Journal, Growth, stats and impersonation skip it the way they skip a
/// director's note, and the cast answers it the same way.
ChatMessage narrationMessage(String text) => ChatMessage(
  text: text,
  sender: 'Narrator',
  isUser: true,
  characterId: kDirectorCharacterId,
  metadata: {kDirectorNarrationMeta: true},
);

/// The beat as the narrator wrote it, minus a leading label or wrapping
/// quotes. Empty when nothing usable came back.
String cleanNarration(String raw) {
  var t = raw.trim();
  t = t.replaceFirst(
    RegExp(r'^(narration|narrator)\s*:\s*', caseSensitive: false),
    '',
  );
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    t = t.substring(1, t.length - 1).trim();
  }
  return t;
}
