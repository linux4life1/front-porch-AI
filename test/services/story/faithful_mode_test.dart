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
import 'package:front_porch_ai/services/story/story_chat_sources.dart';

void main() {
  CharacterCard char() => CharacterCard(
    name: 'Alice',
    description: 'A lighthouse keeper.',
    personality: 'Stoic, warm underneath.',
    scenario: 'A storm-wrecked coast.',
  );

  group('buildChatStoryProject', () {
    test('faithful novella is scoped to the one session and configured', () {
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

  test('a chat with a Setting gives the story that world; none leaves it '
      'unset', () {
    final set = buildChatStoryProject(
      sessionId: 's-1',
      character: char(),
      characterId: 'c-1',
      userName: 'Sam',
      recap: '',
      faithful: true,
      length: 'Novella',
      pov: 'First Person',
      worldId: 'conservatory',
      worldName: 'Greenhollow Estate',
    );
    expect(set.worldId, 'conservatory');
    expect(set.worldName, 'Greenhollow Estate');
    final none = buildChatStoryProject(
      sessionId: 's-1',
      character: char(),
      characterId: 'c-1',
      userName: 'Sam',
      recap: '',
      faithful: true,
      length: 'Novella',
      pov: 'First Person',
      worldId: '',
    );
    expect(none.worldId, isNull);
    expect(none.worldName, '');
  });

  test('faithful directives forbid invention and reordering', () {
    expect(faithfulArchitectDirective, contains('do not reorder'));
    expect(faithfulSceneDirective, contains('without inventing'));
  });

  // Stories from group chats (docs/design/stories-from-group-chats.md §1):
  // the group twin of the builder gives the whole roster, led by the first
  // member unless told otherwise, with the persona a protagonist as in a
  // 1:1 story.
  group('buildGroupStoryProject', () {
    const roster = [
      StoryChatMember(id: 'm-mira', name: 'Mira', description: 'A keeper.'),
      StoryChatMember(id: 'm-dov', name: 'Dov', personality: 'Dry.'),
      StoryChatMember(id: 'm-ash', name: 'Ash', scenario: 'The coast.'),
    ];

    test('three members become a three-member cast led by the first', () {
      final p = buildGroupStoryProject(
        sessionId: 's-g',
        groupId: 'g-1',
        groupName: 'The Lighthouse Crew',
        members: roster,
        userName: 'Sam',
        recap: 'The lamp went out.',
        faithful: true,
        length: 'Novella',
        pov: 'Third Person Limited',
        worldId: 'conservatory',
        worldName: 'Greenhollow Estate',
      );
      expect(p.chatGroupId, 'g-1');
      expect(p.chatGroupName, 'The Lighthouse Crew');
      expect(p.chatHistorySessionIds, ['s-g']);
      expect(p.chatHistoryCharacterIds, ['m-mira', 'm-dov', 'm-ash']);
      expect(p.characterCardSnapshots.map((s) => s['name']), [
        'Mira',
        'Dov',
        'Ash',
      ]);
      expect(p.characterCardSnapshots.map((s) => s['role']), [
        'Protagonist',
        'Supporting',
        'Supporting',
      ]);
      expect(p.characterCardSnapshots.map((s) => s['id']), [
        'm-mira',
        'm-dov',
        'm-ash',
      ]);
      expect(p.characterCardSnapshots.first['description'], 'A keeper.');
      expect(p.includeUserPersona, isTrue);
      expect(p.userPersonaRole, 'Protagonist');
      expect(p.title, 'The Story of The Lighthouse Crew');
      expect(p.concept, contains('between Mira, Dov & Ash and Sam'));
      expect(p.concept, contains('The lamp went out.'));
      expect(p.worldId, 'conservatory');
      expect(p.worldName, 'Greenhollow Estate');
      expect(p.faithfulMode, isTrue);
    });

    test('the lead can be another member or the persona; an unknown lead '
        'falls back to the first member', () {
      StoryProject build(String? lead) => buildGroupStoryProject(
        sessionId: 's-g',
        groupId: 'g-1',
        groupName: '',
        members: roster,
        userName: 'Sam',
        recap: '',
        faithful: false,
        length: 'Short story',
        pov: 'First Person',
        leadId: lead,
      );
      List<String?> roles(StoryProject p) =>
          p.characterCardSnapshots.map((s) => s['role']).toList();
      expect(roles(build('m-ash')), [
        'Supporting',
        'Supporting',
        'Protagonist',
      ]);
      expect(roles(build(kStoryLeadPersona)), [
        'Supporting',
        'Supporting',
        'Supporting',
      ]);
      expect(roles(build('nobody')), [
        'Protagonist',
        'Supporting',
        'Supporting',
      ]);
      // No group name: the roster names the story.
      expect(build(null).title, 'Inspired by Mira, Dov & Ash');
      expect(build(null).actCount, 1);
    });

    test('the group fields round-trip through project JSON and stay absent '
        'for a 1:1 story', () {
      final p = buildGroupStoryProject(
        sessionId: 's-g',
        groupId: 'g-1',
        groupName: 'Crew',
        members: roster,
        userName: 'Sam',
        recap: '',
        faithful: true,
        length: 'Novella',
        pov: 'First Person',
      );
      final back = StoryProject.fromJson(p.toJson());
      expect(back.chatGroupId, 'g-1');
      expect(back.chatGroupName, 'Crew');
      expect(back.chatHistoryCharacterIds, hasLength(3));
      final solo = buildChatStoryProject(
        sessionId: 's-1',
        character: char(),
        characterId: 'c-1',
        userName: 'Sam',
        recap: '',
        faithful: true,
        length: 'Novella',
        pov: 'First Person',
      );
      expect(solo.toJson().containsKey('chat_group_id'), isFalse);
      expect(StoryProject.fromJson(solo.toJson()).chatGroupId, isNull);
    });
  });
}
