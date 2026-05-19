// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/models/lorebook.dart';

void main() {
  group('World', () {
    test('requires name and lorebook', () {
      final world = World(
        name: 'Test World',
        lorebook: Lorebook(entries: []),
      );
      expect(world.name, 'Test World');
      expect(world.lorebook, isNotNull);
    });

    test('toJson includes all fields', () {
      final world = World(
        name: 'Fantasy Realm',
        description: 'A magical world',
        lorebook: Lorebook(entries: [
          LorebookEntry(key: 'magic', content: 'Magic exists here'),
        ]),
        linkedCharacterName: 'Wizard',
        avatarPath: '/path/to/avatar.png',
      );
      final json = world.toJson();
      expect(json['name'], 'Fantasy Realm');
      expect(json['description'], 'A magical world');
      expect(json['lorebook'], isNotNull);
      expect(json['linked_character_name'], 'Wizard');
      expect(json['avatar_path'], '/path/to/avatar.png');
    });

    test('toJson omits null fields', () {
      final world = World(
        name: 'Test World',
        lorebook: Lorebook(entries: []),
      );
      final json = world.toJson();
      expect(json.containsKey('linked_character_name'), false);
      expect(json.containsKey('avatar_path'), false);
    });

    test('fromJson with full data', () {
      final json = {
        'name': 'Dragon Lands',
        'description': 'Land of dragons',
        'lorebook': {
          'entries': [
            {'key': 'dragon', 'content': 'Dragons breathe fire'},
          ],
        },
        'linked_character_name': 'Dragon Master',
        'avatar_path': '/avatars/dragon.png',
      };
      final world = World.fromJson(json);
      expect(world.name, 'Dragon Lands');
      expect(world.description, 'Land of dragons');
      expect(world.lorebook.entries.length, 1);
      expect(world.linkedCharacterName, 'Dragon Master');
      expect(world.avatarPath, '/avatars/dragon.png');
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {
        'name': 'Minimal World',
        'lorebook': {'entries': []},
      };
      final world = World.fromJson(json);
      expect(world.name, 'Minimal World');
      expect(world.description, '');
      expect(world.linkedCharacterName, isNull);
      expect(world.avatarPath, isNull);
    });

    test('fromJson with missing lorebook creates empty lorebook', () {
      final json = {'name': 'No Lorebook World'};
      final world = World.fromJson(json);
      expect(world.name, 'No Lorebook World');
      expect(world.lorebook.entries, isEmpty);
    });

    test('fromJson with null lorebook creates empty lorebook', () {
      final json = {
        'name': 'Null Lorebook World',
        'lorebook': null,
      };
      final world = World.fromJson(json);
      expect(world.name, 'Null Lorebook World');
      expect(world.lorebook.entries, isEmpty);
    });

    test('round-trip preserves all data', () {
      final original = World(
        name: 'Round Trip World',
        description: 'A world that survives serialization',
        lorebook: Lorebook(entries: [
          LorebookEntry(name: 'Entry 1', key: 'a', content: 'Content A'),
          LorebookEntry(name: 'Entry 2', key: 'b', content: 'Content B', constant: true),
        ]),
        linkedCharacterName: 'Hero',
        avatarPath: '/avatars/hero.png',
      );
      final json = original.toJson();
      final restored = World.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.lorebook.entries.length, 2);
      expect(restored.linkedCharacterName, original.linkedCharacterName);
      expect(restored.avatarPath, original.avatarPath);
    });

    test('fromJson handles SillyTavern format (entries at top level as Map)', () {
      // SillyTavern format has no top-level name/description, entries as Map
      final json = {
        'entries': {
          '0': {
            'uid': 0,
            'key': [],
            'keysecondary': [],
            'comment': 'Terran Empire History',
            'content': 'The Terran Empire is a vast interstellar dominion...',
            'constant': true,
            'disable': false,
            'depth': 4,
          },
          '1': {
            'uid': 1,
            'key': ['Terran', 'Empire'],
            'keysecondary': ['blue eyes'],
            'comment': 'Terran traits',
            'content': 'All true-born Terrans possess striking blue eyes...',
            'constant': false,
            'disable': false,
            'depth': 4,
          },
        },
      };
      final world = World.fromJson(json);
      expect(world.name, 'Imported World');
      expect(world.description, '');
      expect(world.lorebook.entries.length, 2);
      expect(world.lorebook.entries[0].name, 'Terran Empire History');
      expect(world.lorebook.entries[0].constant, true);
      expect(world.lorebook.entries[1].name, 'Terran traits');
      expect(world.lorebook.entries[1].key.contains('Terran'), true);
      expect(world.lorebook.entries[1].key.contains('blue eyes'), true);
    });

    test('fromJson handles Chub.ai format with top-level metadata', () {
      // Chub format has name/description at top level, entries as Map
      final json = {
        'name': 'Genshin Impact all characters and locations',
        'description': 'Contains every character and location from Genshin Impact',
        'is_creation': false,
        'scan_depth': 4,
        'token_budget': 530,
        'recursive_scanning': true,
        'extensions': {
          'chub': {
            'id': 2677342,
          },
        },
        'entries': {
          '1': {
            'uid': 1,
            'key': ['Teyvat'],
            'keysecondary': ['Continent', 'Place'],
            'comment': '',
            'content': 'The continent on which {{user}} finds themself.',
            'constant': false,
            'enabled': true,
            'name': 'Teyvat',
            'depth': 4,
          },
          '2': {
            'uid': 2,
            'key': ['Mora'],
            'keysecondary': ['trade', 'Money', 'currency'],
            'comment': '',
            'content': 'Mora is the currency accepted worldwide in Teyvat.',
            'constant': false,
            'enabled': true,
            'name': 'Mora',
            'depth': 4,
          },
        },
      };
      final world = World.fromJson(json);
      expect(world.name, 'Genshin Impact all characters and locations');
      expect(world.description, 'Contains every character and location from Genshin Impact');
      expect(world.lorebook.entries.length, 2);
      expect(world.lorebook.entries[0].name, 'Teyvat');
      expect(world.lorebook.entries[0].key.contains('Continent'), true);
      expect(world.lorebook.entries[1].name, 'Mora');
      expect(world.lorebook.entries[1].key.contains('currency'), true);
    });

    test('fromJson prefers lorebook wrapper over top-level entries', () {
      // If both lorebook.entries and top-level entries exist, lorebook wrapper wins
      final json = {
        'name': 'Test World',
        'lorebook': {
          'entries': [
            {'key': 'from-lorebook', 'content': 'From lorebook wrapper', 'name': 'Wrapper Entry'},
          ],
        },
        'entries': {
          '1': {
            'key': ['from-top-level'],
            'name': 'Top Level Entry',
            'content': 'From top level',
          },
        },
      };
      final world = World.fromJson(json);
      expect(world.name, 'Test World');
      expect(world.lorebook.entries.length, 1);
      expect(world.lorebook.entries[0].name, 'Wrapper Entry');
    });

    test('fromJson handles entries at top level without name (defaults to Imported World)', () {
      final json = {
        'entries': {
          '1': {
            'key': ['test'],
            'name': 'Test Entry',
            'content': 'Test content',
          },
        },
      };
      final world = World.fromJson(json);
      expect(world.name, 'Imported World');
      expect(world.lorebook.entries.length, 1);
    });
  });
}
