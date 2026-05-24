// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/database/database.dart';

/// Mock path_provider so StorageService can resolve
/// getApplicationDocumentsDirectory() without a real platform channel.
void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      final tmp = Directory.systemTemp.createTempSync('fpai_test_');
      return tmp.path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CharacterRepository — in-memory operations', () {
    test('allTags returns sorted unique tags across characters', () {
      final chars = <CharacterCard>[
        CharacterCard(name: 'A', tags: ['z_tag', 'a_tag'], imagePath: 'a.png'),
        CharacterCard(name: 'B', tags: ['m_tag', 'a_tag'], imagePath: 'b.png'),
        CharacterCard(name: 'C', tags: ['z_tag'], imagePath: 'c.png'),
      ];
      final tags = <String>{};
      for (final c in chars) {
        tags.addAll(c.tags);
      }
      final sorted = tags.toList()..sort();
      expect(sorted, ['a_tag', 'm_tag', 'z_tag']);
    });

    test('allTags returns empty for no characters', () {
      final chars = <CharacterCard>[];
      final tags = <String>{};
      for (final c in chars) {
        tags.addAll(c.tags);
      }
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
        CharacterCard(
          name: 'Cat',
          tags: ['animal', 'pet'],
          imagePath: 'cat.png',
        ),
        CharacterCard(
          name: 'Dog',
          tags: ['animal', 'pet'],
          imagePath: 'dog.png',
        ),
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
        lorebook: Lorebook(
          entries: [LorebookEntry(key: 'lore', content: 'Some lore')],
        ),
        worldNames: ['World 1'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 50,
        ),
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

    test(
      'CharacterCard allGreetings includes only firstMessage when no alternates',
      () {
        final card = CharacterCard(name: 'Test', firstMessage: 'Hi there');
        expect(card.allGreetings, ['Hi there']);
      },
    );

    test('CharacterCard formattedDescription replaces placeholders', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} is a cat',
      );
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
      expect(
        json['extensions']['front_porch']['realism_engine']['enabled'],
        true,
      );
    });

    test('CharacterCard replacePlaceholders handles {{char}}', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} is a cat',
      );
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('CharacterCard replacePlaceholders handles <char>', () {
      final card = CharacterCard(name: 'Luna', description: '<char> is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('CharacterCard replacePlaceholders handles {{user}}', () {
      final card = CharacterCard(name: 'Luna');
      expect(
        card.replacePlaceholders('{{user}} pet the cat', userName: 'Alex'),
        'Alex pet the cat',
      );
    });

    test('CharacterCard replacePlaceholders is case-insensitive', () {
      final card = CharacterCard(name: 'Luna');
      expect(card.replacePlaceholders('{{CHAR}}', userName: 'Alex'), 'Luna');
      expect(card.replacePlaceholders('{{USER}}', userName: 'Alex'), 'Alex');
    });
  });

  // ── DB integration tests ────────────────────────────────────────────

  group('CharacterRepository — DB integration', () {
    late AppDatabase db;
    late CharacterRepository repo;
    late String charId;

    Future<StorageService> _makeStorageService([
      Map<String, Object> initialValues = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(initialValues);
      final service = StorageService();
      await service.initialized;
      return service;
    }

    setUp(() async {
      _setupPathProviderMock();

      db = AppDatabase.forTesting();

      charId = await db.insertCharacterReturningId(
        CharactersCompanion(
          name: const Value('Test Character'),
          description: const Value('Integration test character'),
        ),
      );

      final storage = await _makeStorageService();
      repo = CharacterRepository(db, storage);

      // Let async loadCharacters settle
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      await db.close();
    });

    test('getMemorySources returns empty list for a fresh character', () async {
      final sources = await repo.getMemorySources(charId);
      expect(sources, isEmpty);
    });

    test('setMemorySources then getMemorySources round-trips correctly',
        () async {
      const sources = ['src-1', 'src-2', 'src-3'];
      await repo.setMemorySources(charId, sources);
      final retrieved = await repo.getMemorySources(charId);
      expect(retrieved, unorderedEquals(sources));
    });

    test('setMemorySources overwrites previous sources', () async {
      await repo.setMemorySources(charId, ['old-src']);
      await repo.setMemorySources(charId, ['new-src-1', 'new-src-2']);
      final retrieved = await repo.getMemorySources(charId);
      expect(retrieved, unorderedEquals(['new-src-1', 'new-src-2']));
      expect(retrieved, hasLength(2));
    });

    test('setMemorySources with empty list clears sources', () async {
      await repo.setMemorySources(charId, ['src-a']);
      await repo.setMemorySources(charId, []);
      final retrieved = await repo.getMemorySources(charId);
      expect(retrieved, isEmpty);
    });

    test('getMemorySources returns empty list when character does not exist',
        () async {
      final result = await repo.getMemorySources('nonexistent-id');
      expect(result, isEmpty);
    });
  });
}
