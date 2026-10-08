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

// Audio-drama scripts route each labelled line to that character's voice;
// ordinary prose keeps the quote-based split. Proven red by making the
// script detector return null.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story_narration_service.dart';

void main() {
  final cast = [
    StoryCastMember(name: 'Mara Vell', voiceModel: 'voice-mara'),
    StoryCastMember(name: 'Joss Rane'),
  ];

  test('script lines are voiced by speaker label', () {
    const script =
        'NARRATOR: Smoke rolled across the yard.\n'
        'MARA: We leave at dawn.\n'
        'JOSS: You first.\n'
        'NARRATOR: Nobody moved.';
    final segments = StoryNarrationService.parseVoiceSegments(script, cast);
    expect(segments.map((s) => s.text), [
      'Smoke rolled across the yard.',
      'We leave at dawn.',
      'You first.',
      'Nobody moved.',
    ]);
    expect(segments[1].voiceKey, 'voice-mara');
    expect(segments[1].characterName, 'Mara Vell');
    // Joss has no voice picked: narrator voice, but still his line.
    expect(segments[2].voiceKey, isNull);
    expect(segments[2].characterName, 'Joss Rane');
    expect(segments[0].voiceKey, isNull);
  });

  test('prose with a stray "Note:" line is not mistaken for a script', () {
    const prose =
        'Smoke rolled across the yard. "We leave at dawn," Mara said.\n'
        'Nobody moved for a long moment.\n'
        'NOTE: the gate was still open.';
    final segments = StoryNarrationService.parseVoiceSegments(prose, cast);
    expect(segments.length, greaterThan(1));
    expect(segments.any((s) => s.text == 'We leave at dawn,'), isTrue);
    expect(segments.any((s) => s.voiceKey == 'voice-mara'), isTrue);
  });
}
