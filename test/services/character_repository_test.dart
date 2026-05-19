// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';

void main() {
  group('CharacterRepository — in-memory operations', () {
    test('allTags returns sorted unique tags across characters', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'A', tags: ['z_tag', 'a_tag'], imagePath: 'a.png'),
        CharacterCard(name: 'B', tags: ['m_tag', 'a_tag'], imagePath: 'b.png'),
        CharacterCard(name: 'C', tags: ['z_tag'], imagePath: 'c.png'),
      ];
      final tags = <String>{};
      for (final c in chars) tags.addAll(c.tags);
      final sorted = tags.toList()..sort();
      expect(sorted, ['a_tag', 'm_tag', 'z_tag']);
    });

    test('allTags returns empty for no characters', () {
      final chars = <CharacterCard>[];
      final tags = <String>{};
      for (final c in chars) tags.addAll(c.tags);
      expect(tags.toList()..sort(), isEmpty);
    });

    test('getById returns character by dbId', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Find Me', imagePath: 'find.png')..dbId = 'char-1',
        CharacterCard(name: 'Not Me', imagePath: 'not.png')..dbId = 'char-2',
      ];
      final found = chars.where((c) => c.dbId == 'char-1').toList();
      expect(found.length, 1);
      expect(found[0].name, 'Find Me');
    });

    test('getById returns empty for non-existent ID', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Test', imagePath: 'test.png')..dbId = 'char-1',
      ];
      final found = chars.where((c) => c.dbId == 'nonexistent').toList();
      expect(found, isEmpty);
    });

    test('getCharactersByTag filters by tag', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Cat', tags: ['animal', 'pet'], imagePath: 'cat.png'),
        CharacterCard(name: 'Dog', tags: ['animal', 'pet'], imagePath: 'dog.png'),
        CharacterCard(name: 'Car', tags: ['vehicle'], imagePath: 'car.png'),
      ];
      final animals = chars.where((c) => c.tags.contains('animal')).toList();
      expect(animals.length, 2);
    });

    test('getCharactersByTag returns empty when no match', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'Test', tags: ['fantasy'], imagePath: 'test.png'),
      ];
      final sciFi = chars.where((c) => c.tags.contains('scifi')).toList();
      expect(sciFi, isEmpty);
    });

    test('duplicateCharacter creates deep copy with new name', () {
      final original = CharacterCard(
        name: 'Original',
        personality: 'Brave',
        alternateGreetings: ['Hi!', 'Hello!'],
        tags: ['hero'],
        imagePath: 'original.png',
        lorebook: Lorebook(entries: [LorebookEntry(key: 'lore', content: 'Some lore')]),
        worldNames: ['World 1'],
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true, shortTermBond: 50),
        rawExtensions: {'custom': 'data'},
      );

      final cloned = CharacterCard(
        name: '${original.name} (duplicate)',
        description: original.description,
        personality: original.personality,
        scenario: original.scenario,
        firstMessage: original.firstMessage,
        mesExample: original.mesExample,
        systemPrompt: original.systemPrompt,
        postHistoryInstructions: original.postHistoryInstructions,
        alternateGreetings: List.from(original.alternateGreetings),
        tags: List.from(original.tags),
        ttsVoice: original.ttsVoice,
        lorebook: original.lorebook != null
            ? Lorebook(entries: List.from(original.lorebook!.entries))
            : null,
        worldNames: List.from(original.worldNames),
        frontPorchExtensions: original.frontPorchExtensions != null
            ? original.frontPorchExtensions!.copyWith()
            : null,
        rawExtensions: original.rawExtensions != null
            ? Map<String, dynamic>.from(original.rawExtensions!)
            : null,
      );

      expect(cloned.name, 'Original (duplicate)');
      expect(cloned.personality, 'Brave');
      expect(cloned.alternateGreetings, ['Hi!', 'Hello!']);
      expect(cloned.tags, ['hero']);
      expect(cloned.lorebook!.entries.length, 1);
      expect(cloned.frontPorchExtensions!.realismEnabled, true);
      expect(cloned.frontPorchExtensions!.shortTermBond, 50);
      expect(cloned.rawExtensions!['custom'], 'data');

      // Verify deep copy — modifying clone doesn't affect original
      cloned.alternateGreetings.add('Hey!');
      expect(original.alternateGreetings, ['Hi!', 'Hello!']);
    });

    test('duplicateCharacter preserves FrontPorch extensions', () {
      final original = CharacterCard(
        name: 'Ext Character',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 75,
          longTermBond: -20,
          trustLevel: 40,
          dayCount: 10,
          timeOfDay: 'night',
          characterEmotion: 'happy',
          emotionIntensity: 'strong',
          nsfwCooldownEnabled: true,
          passageOfTimeEnabled: false,
          chaosModeEnabled: true,
          currentTask: 'Guard the gate',
        ),
      );

      final cloned = CharacterCard(
        name: '${original.name} (duplicate)',
        frontPorchExtensions: original.frontPorchExtensions!.copyWith(),
      );

      expect(cloned.frontPorchExtensions!.realismEnabled, true);
      expect(cloned.frontPorchExtensions!.shortTermBond, 75);
      expect(cloned.frontPorchExtensions!.longTermBond, -20);
      expect(cloned.frontPorchExtensions!.trustLevel, 40);
      expect(cloned.frontPorchExtensions!.dayCount, 10);
      expect(cloned.frontPorchExtensions!.timeOfDay, 'night');
      expect(cloned.frontPorchExtensions!.characterEmotion, 'happy');
      expect(cloned.frontPorchExtensions!.emotionIntensity, 'strong');
      expect(cloned.frontPorchExtensions!.nsfwCooldownEnabled, true);
      expect(cloned.frontPorchExtensions!.passageOfTimeEnabled, false);
      expect(cloned.frontPorchExtensions!.chaosModeEnabled, true);
      expect(cloned.frontPorchExtensions!.currentTask, 'Guard the gate');
    });

    test('CharacterCard allGreetings combines firstMessage and alternates', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: 'Hello!',
        alternateGreetings: ['Hi!', '', 'Hey!'],
      );
      expect(card.allGreetings, ['Hello!', 'Hi!', 'Hey!']);
    });

    test('CharacterCard allGreetings filters empty entries', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: '',
        alternateGreetings: ['', '', ''],
      );
      expect(card.allGreetings, isEmpty);
    });

    test('CharacterCard allGreetings includes only firstMessage when no alternates', () {
      final card = CharacterCard(name: 'Test', firstMessage: 'Hi there');
      expect(card.allGreetings, ['Hi there']);
    });

    test('CharacterCard formattedDescription replaces placeholders', () {
      final card = CharacterCard(name: 'Luna', description: '{{char}} is a cat');
      expect(card.formattedDescription, 'Luna is a cat');
    });

    test('CharacterCard hasFrontPorchExtensions reflects state', () {
      final card1 = CharacterCard(name: 'No Extensions');
      final card2 = CharacterCard(
        name: 'Has Extensions',
        frontPorchExtensions: FrontPorchExtensions(),
      );
      expect(card1.hasFrontPorchExtensions, false);
      expect(card2.hasFrontPorchExtensions, true);
    });

    test('CharacterCard toJson includes tts_voice when set', () {
      final card = CharacterCard(name: 'Test', ttsVoice: 'en_us');
      final json = card.toJson();
      expect(json['tts_voice'], 'en_us');
    });

    test('CharacterCard toJson omits tts_voice when null', () {
      final card = CharacterCard(name: 'Test');
      final json = card.toJson();
      expect(json.containsKey('tts_voice'), false);
    });

    test('CharacterCard toJson merges rawExtensions with frontPorch', () {
      final card = CharacterCard(
        name: 'Test',
        rawExtensions: {'third_party': 'data'},
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );
      final json = card.toJson();
      expect(json['extensions']['third_party'], 'data');
      expect(json['extensions']['front_porch']['realism_engine']['enabled'], true);
    });

    test('CharacterCard replacePlaceholders handles {{char}}', () {
      final card = CharacterCard(name: 'Luna', description: '{{char}} is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('CharacterCard replacePlaceholders handles <char>', () {
      final card = CharacterCard(name: 'Luna', description: '<char> is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('CharacterCard replacePlaceholders handles {{user}}', () {
      final card = CharacterCard(name: 'Luna');
      expect(card.replacePlaceholders('{{user}} pet the cat', userName: 'Alex'), 'Alex pet the cat');
    });

    test('CharacterCard replacePlaceholders is case-insensitive', () {
      final card = CharacterCard(name: 'Luna');
      expect(card.replacePlaceholders('{{CHAR}}', userName: 'Alex'), 'Luna');
      expect(card.replacePlaceholders('{{USER}}', userName: 'Alex'), 'Alex');
    });
  });
}
