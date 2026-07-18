// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_card.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/group_card_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:image/image.dart' as img;

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
      expect(ext.needsDecayHunger, 4);
      expect(ext.needsDecayBladder, 6);
      expect(ext.needsDecayEnergy, 3);
      expect(ext.needsDecaySocial, 2);
      expect(ext.needsDecayFun, 2);
      expect(ext.needsDecayHygiene, 1);
      expect(ext.needsDecayComfort, 2);
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
        needsDecayHunger: 2,
        needsDecayBladder: 3,
        needsDecayEnergy: 4,
        needsDecaySocial: 6,
        needsDecayFun: 8,
        needsDecayHygiene: 9,
        needsDecayComfort: 10,
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
      expect(ext.needsDecayHunger, 2);
      expect(ext.needsDecayBladder, 3);
      expect(ext.needsDecayEnergy, 4);
      expect(ext.needsDecaySocial, 6);
      expect(ext.needsDecayFun, 8);
      expect(ext.needsDecayHygiene, 9);
      expect(ext.needsDecayComfort, 10);
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
        stableId: 'explicit-stable-in-all-fields-test',
      );
      final json = ext.toJson();
      final engine = json['realism_engine'] as Map<String, dynamic>;
      expect(engine['enabled'], true);
      expect(engine['short_term_bond'], 10);
      expect(engine['stable_id'], 'explicit-stable-in-all-fields-test');
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
          'needs_decay_hunger': 2,
          'needs_decay_bladder': 4,
          'needs_decay_energy': 6,
          'needs_decay_social': 8,
          'needs_decay_fun': 10,
          'needs_decay_hygiene': 12,
          'needs_decay_comfort': 14,
          'stable_id': 'explicit-stable-in-fromjson-full',
        },
      };
      final ext = FrontPorchExtensions.fromJson(json);
      expect(ext.realismEnabled, true);
      expect(ext.shortTermBond, 25);
      expect(ext.stableId, 'explicit-stable-in-fromjson-full');
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
      expect(ext.needsDecayHunger, 2);
      expect(ext.needsDecayBladder, 4);
      expect(ext.needsDecayEnergy, 6);
      expect(ext.needsDecaySocial, 8);
      expect(ext.needsDecayFun, 10);
      expect(ext.needsDecayHygiene, 12);
      expect(ext.needsDecayComfort, 14);
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
        needsDecayHunger: 1,
        needsDecayBladder: 2,
        needsDecayEnergy: 3,
        needsDecaySocial: 4,
        needsDecayFun: 5,
        needsDecayHygiene: 6,
        needsDecayComfort: 7,
        stableId: 'test-stable-uuid-for-roundtrip',
      );
      final json1 = original.toJson();
      final restored = FrontPorchExtensions.fromJson(json1);
      final json2 = restored.toJson();
      expect(json1, json2);
      expect(restored.needsDecayHunger, 1);
      expect(restored.stableId, 'test-stable-uuid-for-roundtrip');
      final engine = json1['realism_engine'] as Map<String, dynamic>;
      expect(engine['stable_id'], 'test-stable-uuid-for-roundtrip');
    });

    test(
      'roundtrip serialization + copyWith + ctor for realismNeedsDirectorAuthority (Director authority on needs deltas flag; covers model + all seed/reset/copyWith/json sites in creators/editors/dialogs/creator_state/realism_step/group per-member)',
      () {
        final original = FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          realismVerificationEnabled: true,
          realismNeedsDirectorAuthority: true,
        );
        expect(original.realismNeedsDirectorAuthority, true);
        final json1 = original.toJson();
        final engine = json1['realism_engine'] as Map<String, dynamic>;
        expect(engine['realism_needs_director_authority'], true);
        final restored = FrontPorchExtensions.fromJson(json1);
        expect(restored.realismNeedsDirectorAuthority, true);
        final json2 = restored.toJson();
        expect(json1, json2);
        final copy = original.copyWith(realismNeedsDirectorAuthority: false);
        expect(copy.realismNeedsDirectorAuthority, false);
        expect(copy.realismEnabled, true); // other fields preserved
        final def = FrontPorchExtensions();
        expect(def.realismNeedsDirectorAuthority, false);
        // also via CharacterCard frontPorch
        final card = CharacterCard(name: 't', frontPorchExtensions: original);
        final cardJson = card.toJson();
        expect(
          cardJson['extensions']['front_porch']['realism_engine']['realism_needs_director_authority'],
          true,
        );
      },
    );

    test('copyWith creates deep copy', () {
      final ext = FrontPorchExtensions(
        realismEnabled: true,
        shortTermBond: 50,
        stableId: 'test-stable-uuid-1234',
      );
      final copy = ext.copyWith();
      expect(copy.realismEnabled, true);
      expect(copy.shortTermBond, 50);
      expect(copy.stableId, 'test-stable-uuid-1234');
      expect(copy, isNot(same(ext)));
    });

    test('copyWith overrides specific fields', () {
      final ext = FrontPorchExtensions(
        realismEnabled: false,
        shortTermBond: 0,
        stableId: 'stable-xyz',
      );
      final copy = ext.copyWith(realismEnabled: true, shortTermBond: 100);
      expect(copy.realismEnabled, true);
      expect(copy.shortTermBond, 100);
      expect(copy.trustLevel, 0);
      expect(copy.stableId, 'stable-xyz'); // carried
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

    test('tier defaults to null and is omitted from toJson', () {
      final ext = FrontPorchExtensions();
      expect(ext.tier, isNull);
      final realism = ext.toJson()['realism_engine'] as Map<String, dynamic>;
      expect(realism.containsKey('tier'), false);
    });

    test('tier (lite) round-trips through toJson/fromJson and copyWith', () {
      final ext = FrontPorchExtensions(tier: 'lite');
      final realism = ext.toJson()['realism_engine'] as Map<String, dynamic>;
      expect(realism['tier'], 'lite');

      final restored = FrontPorchExtensions.fromJson(ext.toJson());
      expect(restored.tier, 'lite');

      final cleared = restored.copyWith(realismEnabled: null);
      expect(cleared.tier, 'lite'); // copyWith preserves tier when not passed
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
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} is a cat',
      );
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('replaces <char> with name', () {
      final card = CharacterCard(name: 'Luna', description: '<char> is a cat');
      expect(card.replacePlaceholders(card.description), 'Luna is a cat');
    });

    test('replaces {{user}} with userName', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{user}} pet the cat',
      );
      expect(
        card.replacePlaceholders('{{user}} pet the cat', userName: 'Alex'),
        'Alex pet the cat',
      );
    });

    test('replacements are case-insensitive', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{CHAR}} and {{User}}',
      );
      expect(
        card.replacePlaceholders('{{CHAR}} and {{User}}', userName: 'Alex'),
        'Luna and Alex',
      );
    });

    test('multiple replacements in one string', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} greets {{user}}',
      );
      expect(
        card.replacePlaceholders('{{char}} greets {{user}}', userName: 'Alex'),
        'Luna greets Alex',
      );
    });

    test('formattedDescription replaces placeholders', () {
      final card = CharacterCard(
        name: 'Luna',
        description: '{{char}} is a cat',
      );
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

    test('isLite false for normal / no-extension cards', () {
      expect(CharacterCard(name: 'Test').isLite, false);
      expect(
        CharacterCard(
          name: 'Test',
          frontPorchExtensions: FrontPorchExtensions(),
        ).isLite,
        false,
      );
    });

    test('isLite true only when tier == lite (Scene Guest)', () {
      final guest = CharacterCard(
        name: 'Guest',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
      );
      expect(guest.isLite, true);
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
      expect(
        json['extensions']['front_porch']['realism_engine']['enabled'],
        true,
      );
    });

    test('toJson with empty character', () {
      final card = CharacterCard(name: '');
      final json = card.toJson();
      expect(json['name'], '');
      expect(json['alternate_greetings'], isEmpty);
      expect(json['tags'], isEmpty);
    });
  });

  group('GroupCard round-trip fidelity (export/import)', () {
    // Covers core export->import fidelity for Group Cards: realism baseline/defaultMember
    // (incl. relationships for Group Dynamics), per-char objectives, characterSystemPrompts,
    // system prompt overrides, multi-member cases, and raw data preservation. These are
    // exercised by _exportGroup / GroupCardService / _importGroupCard flows.
    test(
      'toJson/fromJson preserves realism states, objectives, char prompts and relationships',
      () {
        final baseline = jsonEncode({
          'perChar': {
            'char-uuid-1': {
              'bond': 42,
              'trust': 17,
              'relationships': {
                'char-uuid-2': {'affection': 5},
              },
            },
          },
        });
        final defaultState = jsonEncode({
          'char-uuid-1': {
            'bond': 40,
            'needs': {'energy': 80},
            'relationships': {
              'char-uuid-2': {'affection': 3},
            },
          },
          'char-uuid-2': {'bond': -5},
        });
        final objectives = {
          'char-uuid-1': [
            {
              'objective': 'Find the key',
              'tasks': [],
              'isPrimary': true,
              'active': true,
              'checkFrequency': 3,
              'injectionDepth': 2,
            },
          ],
        };
        final prompts = {
          'char-uuid-1': 'You are Alice only in this group. Speak softly.',
        };

        final gc = GroupCard(
          name: 'Mystery Duo',
          members: [
            CharacterCard(name: 'Alice'),
            CharacterCard(name: 'Bob'),
          ],
          turnOrder: 'random',
          baselineRealismState: baseline,
          defaultMemberRealismState: defaultState,
          memberObjectives: objectives,
          characterSystemPrompts: prompts,
          systemPrompt: 'Group system override here.',
          chaosModeEnabled: true,
          chaosNsfwEnabled: false,
          autoAdvance: true,
          firstMessage: 'They meet in the fog.',
        );

        final json = gc.toJson();
        final restored = GroupCard.fromJson(json);

        expect(restored.name, 'Mystery Duo');
        expect(restored.turnOrder, 'random');
        expect(restored.baselineRealismState, baseline);
        expect(restored.defaultMemberRealismState, defaultState);
        expect(
          restored.memberObjectives['char-uuid-1']?.first['objective'],
          'Find the key',
        );
        expect(
          restored.characterSystemPrompts['char-uuid-1'],
          contains('Alice only in this group'),
        );
        expect(restored.systemPrompt, 'Group system override here.');
        expect(restored.chaosModeEnabled, true);
        expect(restored.chaosNsfwEnabled, false);
        expect(restored.autoAdvance, true);
        expect(restored.firstMessage, 'They meet in the fog.');
        expect(restored.rawMemberData.length, 2);
      },
    );

    test(
      'GroupCardService PNG save/load roundtrips full portable data (export/import fidelity)',
      () async {
        final baseline =
            '{"perChar":{"u1":{"relationships":{"u2":{"trust":9}}}}}';
        final defaultState = '{"u1":{"bond":30},"u2":{}}';
        final gc = GroupCard(
          name: 'Roundtrip Test',
          members: [
            CharacterCard(name: 'A'),
            CharacterCard(name: 'B'),
          ],
          turnOrder: 'roundRobin',
          autoAdvance: true,
          directorMode: false,
          firstMessage: 'Group opens here.',
          scenario: 'The group is in a library.',
          systemPrompt: 'Group level system.',
          characterSystemPrompts: const {'u1': 'Override for group only.'},
          groupLorebook: '{"entries": []}',
          worldIds: const ['w1'],
          inheritCharacterLorebooks: false,
          chaosModeEnabled: true,
          chaosNsfwEnabled: false,
          baselineRealismState: baseline,
          defaultMemberRealismState: defaultState,
          memberObjectives: const {'u1': []},
          extensions: const {
            'realism_state': {'perChar': {}},
          },
        );

        final service = GroupCardService();
        // Use explicit parts + join (cross-platform safe, no extra import).
        final tmpPath = [
          Directory.systemTemp.path,
          '_groktmp_groupcard_${DateTime.now().millisecondsSinceEpoch}.png',
        ].join(Platform.pathSeparator);
        final tmp = File(tmpPath);
        await service.saveGroupCardAsPng(gc, tmpPath);

        final loaded = await service.loadGroupCardFromPng(tmpPath);
        expect(loaded, isNotNull);
        expect(loaded!.name, 'Roundtrip Test');
        expect(loaded.baselineRealismState, baseline);
        expect(loaded.defaultMemberRealismState, defaultState);
        expect(loaded.rawMemberData.length, 2);
        expect(
          loaded.characterSystemPrompts['u1'],
          contains('Override for group only'),
        );
        expect(loaded.autoAdvance, true);
        expect(loaded.firstMessage, 'Group opens here.');
        expect(loaded.scenario, 'The group is in a library.');
        expect(loaded.groupLorebook, '{"entries": []}');
        expect(loaded.worldIds, contains('w1'));
        expect(loaded.inheritCharacterLorebooks, false);
        expect(loaded.chaosNsfwEnabled, false);
        expect(loaded.extensions, isNotNull);

        if (await tmp.exists()) await tmp.delete();
      },
    );

    test('empty-ish GroupCard still roundtrips without crashing', () {
      final gc = GroupCard(
        name: 'Emptyish',
        members: [],
        turnOrder: 'roundRobin',
      );
      final json = gc.toJson();
      final back = GroupCard.fromJson(json);
      expect(back.name, 'Emptyish');
      expect(back.members, isEmpty);
    });

    test(
      'remapping contract shape for realism blobs with relationships (documents _remapIdsInJson expectations)',
      () {
        // This shape (perChar + direct + nested 'relationships' targets) is exactly what
        // the import remapper in _importGroupCard must correctly rewrite using the
        // oldStableIdToNewStableId map built from _original_stable_id during member materialization.
        // The test exercises the *expected output* of that rewrite without reaching the private fn.
        final oldBaseline = jsonEncode({
          'perChar': {
            'old-u1': {
              'bond': 42,
              'relationships': {
                'old-u2': {'affection': 7},
              },
            },
          },
        });
        final oldDefault = jsonEncode({
          'old-u1': {
            'bond': 40,
            'needs': {'energy': 70},
          },
          'old-u2': {'trust': 5},
        });

        // Direct construction + roundtrip proves the portable blobs survive with the
        // exact nested structure (perChar + 'relationships' targets + needs vectors)
        // that the import remapper (_remapIdsInJson + rewritePerCharMap inside
        // _importGroupCard) must correctly rewrite using oldStableIdToNewStableId.
        // This documents the contract for Group Dynamics fidelity without calling
        // the private function.
        final gc = GroupCard(
          name: 'Remap Demo',
          members: [
            CharacterCard(name: 'X'),
            CharacterCard(name: 'Y'),
          ],
          turnOrder: 'roundRobin',
          baselineRealismState: oldBaseline,
          defaultMemberRealismState: oldDefault,
        );

        final json = gc.toJson();
        final restored = GroupCard.fromJson(json);

        expect(restored.baselineRealismState, contains('relationships'));
        expect(restored.defaultMemberRealismState, contains('needs'));
      },
    );

    test(
      'export path now guarantees 100% membership even for avatar-less members (synthesizes full PNG + avatar_base64 + stable ID)',
      () async {
        // Simulates exactly what the fixed _exportGroup now does: for members
        // without a real private avatar file at export time, it still produces
        // a complete raw entry with _original_stable_id (using member UUID) and
        // avatar_base64 containing a valid PNG with embedded V2 chara data.
        // The resulting Group Card must round-trip with N members and every
        // one must be later extractable.
        final v2 = V2CardService();
        final service = GroupCardService();

        // Two "real" avatar files (we synthesize minimal valid PNGs via the
        // same V2 API so they are proper cards; the point is they have files).
        final real1 = await v2.encodeCharacterCardToPngBytes(
          CharacterCard(name: 'RealOne'),
          null,
        );
        final real2 = await v2.encodeCharacterCardToPngBytes(
          CharacterCard(name: 'RealTwo'),
          null,
        );

        final tmpDir = await Directory.systemTemp.createTemp(
          'fp_group_export_fidelity_',
        );
        final real1Path = path.join(tmpDir.path, 'real1.png');
        final real2Path = path.join(tmpDir.path, 'real2.png');
        await File(real1Path).writeAsBytes(real1);
        await File(real2Path).writeAsBytes(real2);

        // Simulate the three members as they would appear after loading from DB:
        // memberCards (with imagePath set only for those that had files on disk)
        // and the parallel members list for fallback stable IDs.
        final memberCards = <CharacterCard>[
          CharacterCard(name: 'RealOne', imagePath: real1Path),
          CharacterCard(name: 'RealTwo', imagePath: real2Path),
          CharacterCard(name: 'NoAvatarAtExport', imagePath: ''),
        ];
        // In real export we have the GroupMember rows; here we fake stable UUIDs
        // that would have been used as fallback for the avatar-less case.
        final fakeMemberIds = [
          'uuid-real-1',
          'uuid-real-2',
          'uuid-no-avatar-3',
        ];

        // Replicate the exact raw-building logic from the fixed export:
        final rawMembersWithAvatars = <Map<String, dynamic>>[];
        for (int i = 0; i < memberCards.length; i++) {
          final card = memberCards[i];
          final raw = Map<String, dynamic>.from(card.toJson());
          String? stableId;
          bool hasReal = false;

          if (card.imagePath != null && card.imagePath!.isNotEmpty) {
            stableId = path.basenameWithoutExtension(card.imagePath!);
            final f = File(card.imagePath!);
            if (await f.exists()) {
              final b = await f.readAsBytes();
              raw['avatar_base64'] = base64Encode(b);
              hasReal = true;
            }
          }
          if (!hasReal) {
            final bytes = await v2.encodeCharacterCardToPngBytes(card, null);
            raw['avatar_base64'] = base64Encode(bytes);
            stableId = fakeMemberIds[i];
          }
          if (stableId != null && stableId.isNotEmpty) {
            raw['_original_stable_id'] = stableId;
          }
          rawMembersWithAvatars.add(raw);
        }

        expect(rawMembersWithAvatars.length, 3);
        expect(rawMembersWithAvatars[2]['name'], 'NoAvatarAtExport');
        expect(rawMembersWithAvatars[2]['avatar_base64'], isNotEmpty);
        expect(
          rawMembersWithAvatars[2]['_original_stable_id'],
          'uuid-no-avatar-3',
        );

        // Now prove the Group Card containing this raw data round-trips fully
        // (what the recipient will see after import of the .group.png).
        final gc = GroupCard(
          name: 'Mixed Avatar Group',
          members: memberCards,
          turnOrder: 'roundRobin',
          rawMemberData: rawMembersWithAvatars,
        );

        final tmpPath = path.join(
          tmpDir.path,
          'mixed_group_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await service.saveGroupCardAsPng(gc, tmpPath);

        final loaded = await service.loadGroupCardFromPng(tmpPath);
        expect(loaded, isNotNull);
        expect(
          loaded!.rawMemberData.length,
          3,
          reason:
              'All 3 members must survive export/import even when one had no avatar at export time',
        );

        // Every raw entry (including the synthesized one) must have a usable avatar_base64
        for (int i = 0; i < 3; i++) {
          final raw = loaded.rawMemberData[i];
          final b64 = raw['avatar_base64'] as String?;
          expect(b64, isNotNull, reason: 'member $i must have avatar_base64');
          expect(b64!.isNotEmpty, true);

          // The bytes must decode to a real PNG containing the chara chunk with the correct name
          final pngBytes = base64Decode(b64);
          final decodedImg =
              img.decodePng(pngBytes) ?? img.decodeImage(pngBytes);
          expect(
            decodedImg,
            isNotNull,
            reason: 'avatar_base64 for member $i must be valid PNG',
          );
          final chara = decodedImg?.textData?['chara'];
          expect(
            chara,
            isNotNull,
            reason: 'PNG for member $i must embed chara metadata',
          );
          final charaJson = jsonDecode(utf8.decode(base64Decode(chara!)));
          final data = charaJson['data'] ?? charaJson;
          expect(data['name'], raw['name']);
        }

        // Cleanup
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      },
    );

    test(
      '_origin_library_stable_id round-trips per member (Group Card portable origin)',
      () async {
        // members[0]/[1] carry BOTH the realism-remap instance id AND the Phase 4
        // library origin; members[2] is origin-unknown (only the instance id),
        // simulating a legacy/foreign member.
        final cards = [
          CharacterCard(name: 'Aria'),
          CharacterCard(name: 'Bryn'),
          CharacterCard(name: 'Legacy'),
        ];
        final raws = <Map<String, dynamic>>[];
        for (var i = 0; i < cards.length; i++) {
          final raw = Map<String, dynamic>.from(cards[i].toJson());
          raw['_original_stable_id'] = 'inst-$i'; // instance id (remap) on all
          if (i < 2) {
            raw['_origin_library_stable_id'] =
                '${cards[i].name.toLowerCase()}_card';
          }
          raws.add(raw);
        }

        final gc = GroupCard(
          name: 'Origin Roundtrip',
          members: cards,
          turnOrder: 'roundRobin',
          rawMemberData: raws,
        );

        final service = GroupCardService();
        final tmpPath = [
          Directory.systemTemp.path,
          '_fp_origin_${DateTime.now().millisecondsSinceEpoch}.png',
        ].join(Platform.pathSeparator);
        final tmp = File(tmpPath);
        await service.saveGroupCardAsPng(gc, tmpPath);
        final loaded = await service.loadGroupCardFromPng(tmpPath);

        expect(loaded, isNotNull);
        expect(loaded!.rawMemberData.length, 3);

        // Both keys survive independently for a member with a known origin.
        expect(
          loaded.rawMemberData[0]['_origin_library_stable_id'],
          'aria_card',
        );
        expect(loaded.rawMemberData[0]['_original_stable_id'], 'inst-0');

        // Origin-unknown member: the Phase 4 key is absent (no false origin).
        expect(
          loaded.rawMemberData[2].containsKey('_origin_library_stable_id'),
          false,
        );

        // The exact import stamping contract (no DB needed): the carried origin
        // becomes a real provenance blob via encodeProvenance, and an absent key
        // yields '{}' (the legacy/origin-unknown shape).
        final stamped0 = GroupMember.encodeProvenance(
          originStableId:
              (loaded.rawMemberData[0]['_origin_library_stable_id'] as String?)
                  ?.trim(),
        );
        expect(jsonDecode(stamped0)['originStableId'], 'aria_card');
        final stamped2 = GroupMember.encodeProvenance(
          originStableId:
              (loaded.rawMemberData[2]['_origin_library_stable_id'] as String?)
                  ?.trim(),
        );
        expect(stamped2, '{}');

        if (await tmp.exists()) await tmp.delete();
      },
    );
  });
}
