// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';

void main() {
  group('FrontPorchExtensions', () {
    test('has correct default values', () {
      final ext = FrontPorchExtensions();
      expect(ext.realismEnabled, false);
      expect(ext.shortTermBond, 0);
      expect(ext.longTermBond, 0);
      expect(ext.trustLevel, 0);
      expect(ext.dayCount, 1);
      expect(ext.timeOfDay, 'morning');
      expect(ext.characterEmotion, '');
      expect(ext.emotionIntensity, 'mild');
      expect(ext.nsfwCooldownEnabled, false);
      expect(ext.passageOfTimeEnabled, true);
      expect(ext.chaosModeEnabled, false);
      expect(ext.currentTask, '');
    });

    test('accepts custom values', () {
      final ext = FrontPorchExtensions(
        realismEnabled: true,
        shortTermBond: 42,
        longTermBond: -10,
        trustLevel: 15,
        dayCount: 7,
        timeOfDay: 'night',
        characterEmotion: 'happy',
        emotionIntensity: 'strong',
        nsfwCooldownEnabled: true,
        passageOfTimeEnabled: false,
        chaosModeEnabled: true,
        currentTask: 'Guard the gate',
      );
      expect(ext.realismEnabled, true);
      expect(ext.shortTermBond, 42);
      expect(ext.longTermBond, -10);
      expect(ext.trustLevel, 15);
      expect(ext.dayCount, 7);
      expect(ext.timeOfDay, 'night');
      expect(ext.characterEmotion, 'happy');
      expect(ext.emotionIntensity, 'strong');
      expect(ext.nsfwCooldownEnabled, true);
      expect(ext.passageOfTimeEnabled, false);
      expect(ext.chaosModeEnabled, true);
      expect(ext.currentTask, 'Guard the gate');
    });

    test('toJson includes version and realism_engine', () {
      final ext = FrontPorchExtensions(realismEnabled: true, shortTermBond: 50);
      final json = ext.toJson();
      expect(json['version'], '2.5');
      final engine = json['realism_engine'] as Map<String, dynamic>;
      expect(engine['enabled'], true);
      expect(engine['short_term_bond'], 50);
    });

    test('toJson includes all fields', () {
      final ext = FrontPorchExtensions(
        realismEnabled: true,
        shortTermBond: 10,
        longTermBond: -5,
        trustLevel: 20,
        dayCount: 3,
        timeOfDay: 'evening',
        characterEmotion: 'angry',
        emotionIntensity: 'moderate',
        nsfwCooldownEnabled: true,
        passageOfTimeEnabled: false,
        chaosModeEnabled: true,
        currentTask: 'Patrol the perimeter',
      );
      final json = ext.toJson();
      final engine = json['realism_engine'] as Map<String, dynamic>;
      expect(engine['enabled'], true);
      expect(engine['short_term_bond'], 10);
      expect(engine['long_term_bond'], -5);
      expect(engine['trust_level'], 20);
      expect(engine['day_count'], 3);
      expect(engine['time_of_day'], 'evening');
      expect(engine['character_emotion'], 'angry');
      expect(engine['emotion_intensity'], 'moderate');
      expect(engine['nsfw_cooldown_enabled'], true);
      expect(engine['passage_of_time_enabled'], false);
      expect(engine['chaos_mode_enabled'], true);
      expect(engine['current_task'], 'Patrol the perimeter');
    });

    test('fromJson with full data', () {
      final json = {
        'version': '2.5',
        'realism_engine': {
          'enabled': true,
          'short_term_bond': 25,
          'long_term_bond': -15,
          'trust_level': 30,
          'day_count': 5,
          'time_of_day': 'afternoon',
          'character_emotion': 'curious',
          'emotion_intensity': 'moderate',
          'nsfw_cooldown_enabled': true,
          'passage_of_time_enabled': false,
          'chaos_mode_enabled': true,
          'current_task': 'Sweep the floor',
        },
      };
      final ext = FrontPorchExtensions.fromJson(json);
      expect(ext.realismEnabled, true);
      expect(ext.shortTermBond, 25);
      expect(ext.longTermBond, -15);
      expect(ext.trustLevel, 30);
      expect(ext.dayCount, 5);
      expect(ext.timeOfDay, 'afternoon');
      expect(ext.characterEmotion, 'curious');
      expect(ext.emotionIntensity, 'moderate');
      expect(ext.nsfwCooldownEnabled, true);
      expect(ext.passageOfTimeEnabled, false);
      expect(ext.chaosModeEnabled, true);
      expect(ext.currentTask, 'Sweep the floor');
    });

    test('fromJson with empty realism_engine', () {
      final json = {'version': '2.5', 'realism_engine': <String, dynamic>{}};
      final ext = FrontPorchExtensions.fromJson(json);
      expect(ext.realismEnabled, false);
      expect(ext.shortTermBond, 0);
      expect(ext.timeOfDay, 'morning');
    });

    test('fromJson with missing realism_engine', () {
      final json = {'version': '2.5'};
      final ext = FrontPorchExtensions.fromJson(json);
      expect(ext.realismEnabled, false);
      expect(ext.shortTermBond, 0);
      expect(ext.dayCount, 1);
    });

    test('fromJson with null values uses defaults', () {
      final json = {
        'version': '2.5',
        'realism_engine': {
          'enabled': null,
          'short_term_bond': null,
          'time_of_day': null,
        },
      };
      final ext = FrontPorchExtensions.fromJson(json);
      expect(ext.realismEnabled, false);
      expect(ext.shortTermBond, 0);
      expect(ext.timeOfDay, 'morning');
    });

    test('round-trip toJson->fromJson->toJson preserves all values', () {
      final original = FrontPorchExtensions(
        realismEnabled: true,
        shortTermBond: 75,
        trustLevel: -20,
        dayCount: 12,
        timeOfDay: 'dawn',
        characterEmotion: 'melancholy',
        emotionIntensity: 'strong',
        chaosModeEnabled: true,
        currentTask: 'Watch the stars',
      );
      final json1 = original.toJson();
      final restored = FrontPorchExtensions.fromJson(json1);
      final json2 = restored.toJson();
      expect(json1, json2);
    });

    test('copyWith creates deep copy', () {
      final ext = FrontPorchExtensions(realismEnabled: true, shortTermBond: 50);
      final copy = ext.copyWith();
      expect(copy.realismEnabled, true);
      expect(copy.shortTermBond, 50);
      expect(copy, isNot(same(ext)));
    });

    test('copyWith overrides specific fields', () {
      final ext = FrontPorchExtensions(realismEnabled: false, shortTermBond: 0);
      final copy = ext.copyWith(realismEnabled: true, shortTermBond: 100);
      expect(copy.realismEnabled, true);
      expect(copy.shortTermBond, 100);
      expect(copy.trustLevel, 0);
    });

    test('copyWith with null uses existing values', () {
      final ext = FrontPorchExtensions(realismEnabled: true, dayCount: 5);
      final copy = ext.copyWith(realismEnabled: null);
      expect(copy.realismEnabled, true);
      expect(copy.dayCount, 5);
    });

    test('copyWith can disable realism', () {
      final ext = FrontPorchExtensions(realismEnabled: true, shortTermBond: 50);
      final copy = ext.copyWith(realismEnabled: false, shortTermBond: 0);
      expect(copy.realismEnabled, false);
      expect(copy.shortTermBond, 0);
    });
  });

  group('CharacterCard', () {
    test('requires name', () {
      final card = CharacterCard(name: 'Test Character');
      expect(card.name, 'Test Character');
    });

    test('has correct defaults for optional fields', () {
      final card = CharacterCard(name: 'Test');
      expect(card.description, '');
      expect(card.personality, '');
      expect(card.scenario, '');
      expect(card.firstMessage, '');
      expect(card.mesExample, '');
      expect(card.systemPrompt, '');
      expect(card.postHistoryInstructions, '');
      expect(card.alternateGreetings, isEmpty);
      expect(card.tags, isEmpty);
      expect(card.imagePath, isNull);
      expect(card.lorebook, isNull);
      expect(card.worldNames, isEmpty);
      expect(card.ttsVoice, isNull);
      expect(card.frontPorchExtensions, isNull);
    });

    test('allGreetings includes firstMessage', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: 'Hello!',
        alternateGreetings: ['Hi there!', 'Hey!'],
      );
      expect(card.allGreetings, ['Hello!', 'Hi there!', 'Hey!']);
    });

    test('allGreetings includes alternate greetings', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: '',
        alternateGreetings: ['Greetings!', 'Salutations!'],
      );
      expect(card.allGreetings, ['Greetings!', 'Salutations!']);
    });

    test('allGreetings filters empty greetings', () {
      final card = CharacterCard(
        name: 'Test',
        firstMessage: '',
        alternateGreetings: ['', 'Valid greeting', ''],
      );
      expect(card.allGreetings, ['Valid greeting']);
    });

    test('replaces {{char}} with name', () {
      final card = CharacterCard(name: 'Luna', description: '{{char}} is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('replaces <char> with name', () {
      final card = CharacterCard(name: 'Luna', description: '<char> is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('replaces {{user}} with userName', () {
      final card = CharacterCard(name: 'Luna', description: '{{user}} pet the cat');
      expect(card.replacePlaceholders('{{user}} pet the cat', userName: 'Alex'), 'Alex pet the cat');
    });

    test('replacements are case-insensitive', () {
      final card = CharacterCard(name: 'Luna', description: '{{CHAR}} and {{User}}');
      expect(card.replacePlaceholders('{{CHAR}} and {{User}}', userName: 'Alex'), 'Luna and Alex');
    });

    test('multiple replacements in one string', () {
      final card = CharacterCard(name: 'Luna', description: '{{char}} greets {{user}}');
      expect(card.replacePlaceholders('{{char}} greets {{user}}', userName: 'Alex'), 'Luna greets Alex');
    });

    test('formattedDescription replaces placeholders', () {
      final card = CharacterCard(name: 'Luna', description: '{{char}} is a cat');
      expect(card.formattedDescription, 'Luna is a cat');
    });

    test('hasFrontPorchExtensions false when null', () {
      final card = CharacterCard(name: 'Test');
      expect(card.hasFrontPorchExtensions, false);
    });

    test('hasFrontPorchExtensions true when set', () {
      final card = CharacterCard(
        name: 'Test',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );
      expect(card.hasFrontPorchExtensions, true);
    });

    test('toJson includes all fields', () {
      final card = CharacterCard(
        name: 'Luna',
        description: 'A cat',
        personality: 'Friendly',
        scenario: 'In a garden',
        firstMessage: 'Meow!',
        mesExample: 'Example dialogue',
        systemPrompt: 'Be nice',
        postHistoryInstructions: 'Keep it short',
        alternateGreetings: ['Hello!'],
        tags: ['cat', 'pet'],
        lorebook: Lorebook(entries: []),
        worldNames: ['Garden World'],
        frontPorchExtensions: FrontPorchExtensions(),
      );
      final json = card.toJson();
      expect(json['name'], 'Luna');
      expect(json['description'], 'A cat');
      expect(json['personality'], 'Friendly');
      expect(json['scenario'], 'In a garden');
      expect(json['first_mes'], 'Meow!');
      expect(json['mes_example'], 'Example dialogue');
      expect(json['system_prompt'], 'Be nice');
      expect(json['post_history_instructions'], 'Keep it short');
      expect(json['alternate_greetings'], ['Hello!']);
      expect(json['tags'], ['cat', 'pet']);
      expect(json['character_book'], isNotNull);
      expect(json['world_names'], ['Garden World']);
      expect(json['extensions'], isNotNull);
    });

    test('toJson includes tts_voice when set', () {
      final card = CharacterCard(name: 'Test', ttsVoice: 'en_us');
      final json = card.toJson();
      expect(json['tts_voice'], 'en_us');
    });

    test('toJson omits tts_voice when null', () {
      final card = CharacterCard(name: 'Test');
      final json = card.toJson();
      expect(json.containsKey('tts_voice'), false);
    });

    test('toJson preserves rawExtensions', () {
      final card = CharacterCard(
        name: 'Test',
        rawExtensions: {'third_party': 'data'},
      );
      final json = card.toJson();
      expect(json['extensions']['third_party'], 'data');
    });

    test('toJson merges rawExtensions with frontPorch', () {
      final card = CharacterCard(
        name: 'Test',
        rawExtensions: {'third_party': 'data'},
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );
      final json = card.toJson();
      expect(json['extensions']['third_party'], 'data');
      expect(json['extensions']['front_porch']['realism_engine']['enabled'], true);
    });

    test('toJson with empty character', () {
      final card = CharacterCard(name: '');
      final json = card.toJson();
      expect(json['name'], '');
      expect(json['alternate_greetings'], isEmpty);
      expect(json['tags'], isEmpty);
    });
  });
}
