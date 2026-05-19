// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';

void main() {
  group('LorebookEntry', () {
    test('displayName returns name when available', () {
      final entry = LorebookEntry(name: 'My Entry', key: 'test', content: 'some content');
      expect(entry.displayName, 'My Entry');
    });

    test('displayName returns key when name is empty', () {
      final entry = LorebookEntry(name: '', key: 'test-key', content: 'some content');
      expect(entry.displayName, 'test-key');
    });

    test('displayName returns "Unnamed Entry" when both empty', () {
      final entry = LorebookEntry(name: '', key: '', content: 'some content');
      expect(entry.displayName, 'Unnamed Entry');
    });

    test('toJson includes all fields with proper keys', () {
      final entry = LorebookEntry(
        name: 'Test Entry',
        key: 'hello,hi',
        content: 'A greeting rule',
        enabled: true,
        constant: true,
        stickyDepth: 3,
      );
      final json = entry.toJson();
      expect(json['name'], 'Test Entry');
      expect(json['key'], 'hello,hi');
      expect(json['keys'], ['hello', 'hi']);
      expect(json['content'], 'A greeting rule');
      expect(json['enabled'], true);
      expect(json['constant'], true);
      expect(json['sticky_depth'], 3);
    });

    test('toJson trims and filters empty keys', () {
      final entry = LorebookEntry(key: 'hello, , world , ', content: 'some content');
      final json = entry.toJson();
      expect(json['keys'], ['hello', 'world']);
    });

    test('fromJson handles V2 keys array', () {
      final json = {
        'name': 'Greeting',
        'keys': ['hello', 'hi', 'hey'],
        'content': 'Say hello back',
        'enabled': true,
        'constant': false,
        'sticky_depth': 2,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, 'Greeting');
      expect(entry.key, 'hello, hi, hey');
      expect(entry.content, 'Say hello back');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 2);
    });

    test('fromJson handles V1 key string', () {
      final json = {
        'name': 'Old Entry',
        'key': 'trigger-word',
        'content': 'Content here',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, 'trigger-word');
      expect(entry.name, 'Old Entry');
      expect(entry.content, 'Content here');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 1);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {'key': 'test', 'content': 'some content'};
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, '');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 1);
    });

    test('fromJson handles insertion_order fallback for stickyDepth', () {
      final json = {
        'key': 'test',
        'content': 'content',
        'insertion_order': 5,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.stickyDepth, 5);
    });

    test('round-trip preserves data', () {
      final original = LorebookEntry(
        name: 'Round Trip Test',
        key: 'trigger1, trigger2',
        content: 'This content must survive round-trip',
        enabled: true,
        constant: true,
        stickyDepth: 4,
      );
      final json = original.toJson();
      final restored = LorebookEntry.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.key, original.key);
      expect(restored.content, original.content);
      expect(restored.enabled, original.enabled);
      expect(restored.constant, original.constant);
      expect(restored.stickyDepth, original.stickyDepth);
    });
  });

  group('Lorebook', () {
    test('fromJson with entries', () {
      final json = {
        'entries': [
          {'key': 'hello', 'content': 'Greeting', 'name': 'Greet Rule'},
          {'key': 'goodbye', 'content': 'Farewell', 'name': 'Farewell Rule'},
        ],
      };
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries.length, 2);
      expect(lorebook.entries[0].key, 'hello');
      expect(lorebook.entries[1].key, 'goodbye');
    });

    test('fromJson with empty entries list', () {
      final json = {'entries': []};
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries, isEmpty);
    });

    test('fromJson with missing entries', () {
      final json = <String, dynamic>{};
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries, isEmpty);
    });

    test('fromJson with null entries', () {
      final json = {'entries': null};
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries, isEmpty);
    });

    test('toJson includes all entries', () {
      final lorebook = Lorebook(entries: [
        LorebookEntry(key: 'a', content: 'Content A'),
        LorebookEntry(key: 'b', content: 'Content B'),
      ]);
      final json = lorebook.toJson();
      expect(json['entries'], isA<List>());
      expect(json['entries'].length, 2);
    });

    test('toJson with empty entries', () {
      final lorebook = Lorebook(entries: []);
      final json = lorebook.toJson();
      expect(json['entries'], isEmpty);
    });

    test('round-trip preserves all entries', () {
      final original = Lorebook(entries: [
        LorebookEntry(name: 'Entry 1', key: 'trigger1', content: 'Content 1', constant: true),
        LorebookEntry(name: 'Entry 2', key: 'trigger2, trigger3', content: 'Content 2', stickyDepth: 3),
      ]);
      final json = original.toJson();
      final restored = Lorebook.fromJson(json);
      expect(restored.entries.length, 2);
      expect(restored.entries[0].name, 'Entry 1');
      expect(restored.entries[1].name, 'Entry 2');
      expect(restored.entries[1].key, 'trigger2, trigger3');
    });

    test('fromJson handles SillyTavern format (entries as Map)', () {
      // SillyTavern exports entries as {"0": {...}, "1": {...}}
      final json = {
        'entries': {
          '0': {
            'uid': 0,
            'key': [],
            'keysecondary': [],
            'comment': 'Terran Empire History',
            'content': 'The Terran Empire is a vast interstellar dominion...',
            'constant': true,
            'vectorized': false,
            'selective': true,
            'selectiveLogic': 0,
            'addMemo': true,
            'order': 100,
            'position': 0,
            'disable': false,
            'ignoreBudget': false,
            'excludeRecursion': false,
            'preventRecursion': false,
            'matchPersonaDescription': false,
            'matchCharacterDescription': false,
            'matchCharacterPersonality': false,
            'matchCharacterDepthPrompt': false,
            'matchScenario': false,
            'matchCreatorNotes': false,
            'delayUntilRecursion': false,
            'probability': 100,
            'useProbability': true,
            'depth': 4,
            'outletName': '',
            'group': '',
            'groupOverride': false,
            'groupWeight': 100,
            'scanDepth': null,
            'caseSensitive': null,
            'matchWholeWords': null,
            'useGroupScoring': null,
            'automationId': '',
            'role': null,
            'sticky': 0,
            'cooldown': 0,
            'delay': 0,
            'triggers': [],
            'displayIndex': 0,
            'characterFilter': {'isExclude': false, 'names': [], 'tags': []},
          },
          '1': {
            'uid': 1,
            'key': ['Terran', 'Empire'],
            'keysecondary': ['blue eyes', 'fair skin'],
            'comment': 'Terran traits',
            'content': 'All true-born Terrans possess striking blue eyes...',
            'constant': false,
            'disable': false,
            'depth': 4,
            'probability': 100,
            'useProbability': true,
            'addMemo': true,
            'selective': false,
            'selectiveLogic': 0,
            'order': 100,
            'position': 0,
            'displayIndex': 1,
          },
        },
      };
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries.length, 2);

      // Entry 0: constant entry with empty keys, name from comment
      expect(lorebook.entries[0].name, 'Terran Empire History');
      expect(lorebook.entries[0].key, '');
      expect(lorebook.entries[0].content.contains('Terran Empire'), true);
      expect(lorebook.entries[0].constant, true);
      expect(lorebook.entries[0].enabled, true);

      // Entry 1: keys from key[] + keysecondary[]
      expect(lorebook.entries[1].name, 'Terran traits');
      expect(lorebook.entries[1].key.contains('Terran'), true);
      expect(lorebook.entries[1].key.contains('Empire'), true);
      expect(lorebook.entries[1].key.contains('blue eyes'), true);
      expect(lorebook.entries[1].key.contains('fair skin'), true);
      expect(lorebook.entries[1].constant, false);
      expect(lorebook.entries[1].enabled, true);
    });

    test('fromJson handles Chub.ai format (entries as Map with extra fields)', () {
      // Chub exports entries as {"1": {...}, "2": {...}} with extra metadata
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
            'full_path': 'lorebooks/Legodude/genshin-impact-all-characters-and-locations-0a988c0432cd',
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
            'selective': false,
            'selectiveLogic': 0,
            'order': 10,
            'position': 1,
            'disable': false,
            'addMemo': true,
            'excludeRecursion': true,
            'probability': 100,
            'displayIndex': 1,
            'useProbability': true,
            'secondary_keys': ['Continent', 'Place'],
            'keys': ['Teyvat'],
            'id': 1,
            'priority': 3,
            'insertion_order': 10,
            'enabled': true,
            'name': 'Teyvat',
            'extensions': {
              'depth': 4,
              'weight': 10,
            },
            'case_sensitive': false,
            'depth': 4,
          },
          '2': {
            'uid': 2,
            'key': ['Mora'],
            'keysecondary': ['trade', 'barter', 'Money', 'currency'],
            'comment': '',
            'content': 'Mora is the currency that is accepted worldwide in Teyvat.',
            'constant': false,
            'disable': false,
            'enabled': true,
            'name': 'Mora',
            'keys': ['Mora'],
            'secondary_keys': ['trade', 'barter', 'Money', 'currency'],
            'id': 2,
            'depth': 4,
          },
        },
      };
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries.length, 2);

      // Entry 1: Teyvat
      expect(lorebook.entries[0].name, 'Teyvat');
      expect(lorebook.entries[0].key.contains('Teyvat'), true);
      expect(lorebook.entries[0].key.contains('Continent'), true);
      expect(lorebook.entries[0].key.contains('Place'), true);
      expect(lorebook.entries[0].content.contains('continent'), true);
      expect(lorebook.entries[0].enabled, true);
      expect(lorebook.entries[0].constant, false);

      // Entry 2: Mora
      expect(lorebook.entries[1].name, 'Mora');
      expect(lorebook.entries[1].key.contains('Mora'), true);
      expect(lorebook.entries[1].key.contains('trade'), true);
      expect(lorebook.entries[1].key.contains('currency'), true);
      expect(lorebook.entries[1].enabled, true);
    });

    test('fromJson handles disabled entries (SillyTavern disable field)', () {
      final json = {
        'entries': {
          '0': {
            'key': ['test'],
            'comment': 'Disabled entry',
            'content': 'This is disabled',
            'disable': true,
            'constant': false,
          },
          '1': {
            'key': ['test2'],
            'comment': 'Enabled entry',
            'content': 'This is enabled',
            'disable': false,
            'constant': false,
          },
        },
      };
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries[0].enabled, false);
      expect(lorebook.entries[1].enabled, true);
    });

    test('fromJson handles Chub enabled field', () {
      final json = {
        'entries': {
          '1': {
            'key': ['test'],
            'name': 'Disabled',
            'content': 'Disabled content',
            'enabled': false,
          },
          '2': {
            'key': ['test2'],
            'name': 'Enabled',
            'content': 'Enabled content',
            'enabled': true,
          },
        },
      };
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries[0].enabled, false);
      expect(lorebook.entries[1].enabled, true);
    });

    test('parseRawLorebookJson extracts name and description', () {
      final json = {
        'name': 'My Lorebook',
        'description': 'A test lorebook',
        'entries': {
          '1': {
            'key': ['test'],
            'name': 'Test Entry',
            'content': 'Content',
          },
        },
      };
      final result = Lorebook.parseRawLorebookJson(json);
      expect(result['name'], 'My Lorebook');
      expect(result['description'], 'A test lorebook');
      expect(result['lorebook'], isA<Map>());
      expect(result['lorebook']['entries'].length, 1);
    });
  });

  group('LorebookEntry cross-format compatibility', () {
    test('handles key as empty array (SillyTavern)', () {
      final json = {
        'key': [],
        'comment': 'Empty keys',
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, '');
      expect(entry.name, 'Empty keys');
    });

    test('handles key as single string', () {
      final json = {
        'key': 'single-key',
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, 'single-key');
    });

    test('handles key as comma-separated string', () {
      final json = {
        'key': 'key1, key2, key3',
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, 'key1, key2, key3');
    });

    test('handles keys array (Chub duplicate field)', () {
      final json = {
        'keys': ['alpha', 'beta'],
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, 'alpha, beta');
    });

    test('merges keys and secondary_keys (Chub)', () {
      final json = {
        'keys': ['primary'],
        'secondary_keys': ['secondary1', 'secondary2'],
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key.contains('primary'), true);
      expect(entry.key.contains('secondary1'), true);
      expect(entry.key.contains('secondary2'), true);
    });

    test('merges key and keysecondary (SillyTavern)', () {
      final json = {
        'key': ['primary'],
        'keysecondary': ['secondary1', 'secondary2'],
        'comment': 'Merged keys',
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, 'Merged keys');
      expect(entry.key.contains('primary'), true);
      expect(entry.key.contains('secondary1'), true);
      expect(entry.key.contains('secondary2'), true);
    });

    test('uses comment as name fallback (SillyTavern)', () {
      final json = {
        'key': ['test'],
        'comment': 'Entry from comment',
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, 'Entry from comment');
    });

    test('prefers name over comment (Chub)', () {
      final json = {
        'key': ['test'],
        'name': 'Name field',
        'comment': 'Comment field',
        'content': 'Content',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, 'Name field');
    });

    test('handles depth field for stickyDepth (SillyTavern)', () {
      final json = {
        'key': ['test'],
        'content': 'Content',
        'depth': 8,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.stickyDepth, 8);
    });

    test('handles sticky field for stickyDepth', () {
      final json = {
        'key': ['test'],
        'content': 'Content',
        'sticky': 3,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.stickyDepth, 3);
    });

    test('handles insertion_order for stickyDepth', () {
      final json = {
        'key': ['test'],
        'content': 'Content',
        'insertion_order': 7,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.stickyDepth, 7);
    });

    test('handles null values gracefully', () {
      final json = {
        'key': null,
        'name': null,
        'content': null,
        'enabled': null,
        'constant': null,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, '');
      expect(entry.name, '');
      expect(entry.content, '');
      expect(entry.enabled, true);
      expect(entry.constant, false);
    });

    test('handles completely empty JSON', () {
      final json = <String, dynamic>{};
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, '');
      expect(entry.name, '');
      expect(entry.content, '');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 1);
    });
  });
}
