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

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/story/faithful_mode.dart';

void main() {
  CharacterCard char() => CharacterCard(
    name: 'Alice',
    description: 'A lighthouse keeper.',
    personality: 'Stoic, warm underneath.',
    scenario: 'A storm-wrecked coast.',
  );

  group('buildChatStoryProject', () {
    test('faithful novella is scoped to the one session and configured',
        () {
      final p = buildChatStoryProject(
        sessionId: 's-1',
        character: char(),
        characterId: 'c-1',
        userName: 'Sam',
        recap: 'They finally spoke about the wreck.',
        faithful: true,
        length: 'Novella',
        pov: 'First Person',
      );
      expect(p.useChatHistory, isTrue);
      expect(p.chatHistorySessionIds, ['s-1']);
      expect(p.chatHistoryCharacterIds, ['c-1']);
      expect(p.faithfulMode, isTrue);
      expect(p.actCount, 3);
      expect(p.proseLength, 'Standard');
      expect(p.pov, 'First Person');
      expect(p.concept, contains('faithful novelization'));
      expect(p.concept, contains('They finally spoke about the wreck.'));
      expect(p.characterCardSnapshots.single['name'], 'Alice');
      expect(p.includeUserPersona, isTrue);
    });

    test('short story shrinks to one act; inspired mode relaxes', () {
      final p = buildChatStoryProject(
        sessionId: 's-1',
        character: char(),
        characterId: 'c-1',
        userName: 'Sam',
        recap: '',
        faithful: false,
        length: 'Short story',
        pov: 'Third Person Limited',
      );
      expect(p.faithfulMode, isFalse);
      expect(p.actCount, 1);
      expect(p.proseLength, 'Short');
      expect(p.concept, contains('inspired by'));
      expect(p.concept, isNot(contains('Where the story stands')));
    });

    test('new fields round-trip through project JSON (additive)', () {
      final p = buildChatStoryProject(
        sessionId: 's-9',
        character: char(),
        characterId: 'c-9',
        userName: 'Sam',
        recap: '',
        faithful: true,
        length: 'Novella',
        pov: 'First Person',
      );
      final back = StoryProject.fromJson(p.toJson());
      expect(back.chatHistorySessionIds, ['s-9']);
      expect(back.faithfulMode, isTrue);
      // And an OLD project json (without the new keys) stays default-safe.
      final legacy = StoryProject.fromJson({'title': 'old'});
      expect(legacy.chatHistorySessionIds, isEmpty);
      expect(legacy.faithfulMode, isFalse);
    });
  });

  test('faithful directives forbid invention and reordering', () {
    expect(faithfulArchitectDirective, contains('do not reorder'));
    expect(faithfulSceneDirective, contains('without inventing'));
  });
}
