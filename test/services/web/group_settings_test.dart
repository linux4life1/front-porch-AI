// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/group_facade.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook_import.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.createTempSync('fpai_docs_').path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('GroupFacade.updateSettings', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      groups = GroupChatRepository(storage, db);
      await groups.save(GroupChat(id: 'g1', name: 'Original'));
      facade = GroupFacade(groups, storage);
    });

    tearDown(() => db.close());

    test('updates settings-only fields and persists', () async {
      expect(
        await facade.updateSettings('g1', {
          'name': 'Renamed',
          'systemPrompt': 'Be terse.',
          'scenario': 'A tavern',
          'turnOrder': 'random',
          'characterSystemPrompts': {'alice': 'whisper', 'bram': 'shout'},
        }),
        isTrue,
      );

      final g = groups.getById('g1')!;
      expect(g.name, 'Renamed');
      expect(g.systemPrompt, 'Be terse.');
      expect(g.scenario, 'A tavern');
      expect(g.turnOrder.name, 'random');
      expect(g.characterSystemPrompts['alice'], 'whisper');
      expect(g.characterSystemPrompts['bram'], 'shout');
    });

    test('unknown group returns false', () async {
      expect(await facade.updateSettings('nope', {'name': 'x'}), isFalse);
    });

    test(
      'updateSettings compact-pairs dirty empty greet so furious does not land on Get out',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['', 'Get out.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason:
              "['', 'Get out.']+[furious] must not load furious onto Get out",
        );
        expect(g.allGreetings, ['Come in.', 'Get out.']);
        expect(
          greetingOverlayAt(g.greetingSeeds, 1),
          isNull,
          reason: 'live overlay must already be paired, not only after reload',
        );
      },
    );

    test(
      'updateSettings JSON-null greet slot keeps furious on Get out',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': [null, 'Get out.'],
            'greetingSeeds': [
              null,
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(g.greetingSeeds.single!.characterEmotion, 'furious');
        expect(
          greetingOverlayAt(g.greetingSeeds, 1)!.characterEmotion,
          'furious',
        );
      },
    );

    test(
      'updateSettings clean alts-only POST drops leftover [furious] off Get out',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          groups.getById('g1')!.greetingSeeds.single!.characterEmotion,
          'furious',
        );
        expect(
          await facade.updateSettings('g1', {
            'alternateGreetings': ['Get out.'],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason:
              "['Get out.'] omit seeds must not reuse unpaired existing [furious]",
        );
        expect(
          greetingOverlayAt(g.greetingSeeds, 1),
          isNull,
          reason: 'Get out overlay is not leftover furious',
        );
      },
    );

    test(
      'updateSettings dirty alts-only POST drops leftover [furious] off Get out',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          await facade.updateSettings('g1', {
            'alternateGreetings': ['', 'Get out.'],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason:
              'dirty alts-only + existing [furious] must not load furious onto Get out',
        );
        expect(
          greetingOverlayAt(g.greetingSeeds, 1),
          isNull,
          reason: 'Get out overlay is not leftover furious',
        );
      },
    );

    test(
      'updateSettings explicit empty greetingSeeds stays authored-empty',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          await facade.updateSettings('g1', {
            'alternateGreetings': ['Get out.'],
            'greetingSeeds': [],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason:
              'explicit empty greetingSeeds is authored-empty, not leftover furious',
        );
        expect(greetingOverlayAt(g.greetingSeeds, 1), isNull);
      },
    );

    test(
      'updateSettings omitted alts keep base seeds',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          await facade.updateSettings('g1', {
            'name': 'Renamed-keep-seeds',
            'systemPrompt': 'Be terse.',
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.name, 'Renamed-keep-seeds');
        expect(g.alternateGreetings, ['Stay.']);
        expect(
          g.greetingSeeds.single!.characterEmotion,
          'furious',
          reason: 'omitted alts must not wipe leftover base seeds',
        );
      },
    );

    test(
      'updateSettings dirty alts + explicit empty greetingSeeds stays authored-empty',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          await facade.updateSettings('g1', {
            'alternateGreetings': ['', 'Get out.'],
            'greetingSeeds': [],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason:
              'explicit [] on dirty alts is authored-empty, not leftover furious',
        );
        expect(greetingOverlayAt(g.greetingSeeds, 1), isNull);
      },
    );

    test(
      'updateSettings explicit empty greetingSeeds without alts stays authored-empty',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          await facade.updateSettings('g1', {
            'greetingSeeds': [],
          }),
          isTrue,
        );
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Stay.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason: 'explicit empty is authored-empty, not dropped as omit',
        );
        expect(greetingOverlayAt(g.greetingSeeds, 1), isNull);
      },
    );

    test(
      'updateSettings omitted seeds persist empty after reload and toJson/fromJson',
      () async {
        expect(
          await facade.updateSettings('g1', {
            'firstMessage': 'Come in.',
            'alternateGreetings': ['Stay.'],
            'greetingSeeds': [
              {'characterEmotion': 'furious'},
            ],
          }),
          isTrue,
        );
        expect(
          await facade.updateSettings('g1', {
            'alternateGreetings': ['Get out.'],
          }),
          isTrue,
        );
        await groups.reload();
        final g = groups.getById('g1')!;
        expect(g.alternateGreetings, ['Get out.']);
        expect(
          g.greetingSeeds,
          isEmpty,
          reason:
              "reload after ['Get out.'] omit seeds must not load leftover furious",
        );
        expect(
          greetingOverlayAt(g.greetingSeeds, 1),
          isNull,
          reason: 'persisted Get out overlay is not leftover furious',
        );

        final restored = GroupChat.fromJson(g.toJson());
        expect(restored.alternateGreetings, ['Get out.']);
        expect(
          restored.greetingSeeds,
          isEmpty,
          reason: '1:1 apply/restore must not resurrect leftover furious',
        );
        expect(greetingOverlayAt(restored.greetingSeeds, 1), isNull);
      },
    );
  });

  // Web parity for the new-group wizard: the PWA used to post only a name,
  // members and a turn order, so a web-made group had none of the Opening,
  // Realism, Group Dynamics or Prompts & Lore the desktop wizard sets. The
  // relay now reads the whole draft. Proven to fail: drop GroupCreateDraft
  // from GroupFacade.createGroup and every expectation below goes red.
  group('GroupFacade.createGroup with the wizard draft', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupFacade facade;
    late List<String> ids;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final chars = CharacterRepository(db, storage);
      for (final n in ['Juniper', 'Marlow']) {
        await chars.addCharacter(
          CharacterCard(name: n, description: 'Only in the draft test.'),
        );
      }
      ids = [for (final c in chars.characters) c.dbId!];
      groups = GroupChatRepository(storage, db);
      facade = GroupFacade(groups, storage, chars, db);
    });

    tearDown(() => db.close());

    test(
      'every step of the draft lands on the group and its members',
      () async {
        final made = await facade.createGroup({
          'name': 'Porch Regulars',
          'memberIds': ids,
          'autoAdvance': true,
          'directorMode': true,
          'scenario': 'Rain on the porch roof.',
          'firstMessage': 'The screen door bangs.',
          'alternateGreetings': ['A second way in.'],
          'systemPrompt': 'Keep it cosy.',
          'memberPrompts': {ids[0]: 'Speak in riddles.'},
          'groupLore': [
            {
              'name': 'The swing',
              'keys': ['swing'],
              'content': 'It creaks.',
            },
            {'content': 'Always summer here.', 'constant': true},
          ],
          'inheritCharacterLorebooks': true,
          'realism': {
            'enabled': true,
            'needsEnabled': false,
            'timeOfDay': 'evening',
            'dayCount': 3,
            'members': {
              ids[0]: {'affection': 70, 'trust': 60},
            },
            'relationships': {
              ids[0]: {ids[1]: 120},
            },
          },
        });
        await groups.reload();
        final g = groups.getById(made!['id'] as String)!;
        final members = await groups.getMembersForGroup(g.id);
        final midOf = {for (final m in members) m.originLibraryDbId: m.id};
        expect(g.autoAdvance, isTrue);
        expect(g.directorMode, isTrue);
        expect(g.scenario, 'Rain on the porch roof.');
        expect(g.firstMessage, 'The screen door bangs.');
        expect(g.alternateGreetings, ['A second way in.']);
        expect(g.systemPrompt, 'Keep it cosy.');
        expect(g.characterSystemPrompts, {midOf[ids[0]]: 'Speak in riddles.'});
        expect(g.inheritCharacterLorebooks, isTrue);
        final lore = parseGroupLorebookJson(g.groupLorebook)!.entries;
        expect(lore.map((e) => e.content), [
          'It creaks.',
          'Always summer here.',
        ]);
        expect(lore.last.constant, isTrue);

        final seeds = parseGroupRealismSeeds(g.defaultMemberRealismState);
        expect(seeds.keys.toSet(), midOf.values.toSet());
        final jun = seeds[midOf[ids[0]]]!;
        expect(jun['affection'], 70);
        expect(jun['trust'], 60);
        expect(jun['relationships'], {midOf[ids[1]]: 120});
        expect(jun.containsKey('needs'), isFalse, reason: 'needs was off');
        expect(
          parseGroupTimeSeed(
            g.defaultMemberRealismState,
            g.baselineRealismState,
          )!.timeOfDay,
          'evening',
        );
      },
    );

    test('realism off stores no member seeds', () async {
      final made = await facade.createGroup({
        'name': 'Quiet',
        'memberIds': ids,
        'realism': {'enabled': false},
      });
      await groups.reload();
      final g = groups.getById(made!['id'] as String)!;
      expect(parseGroupRealismSeeds(g.defaultMemberRealismState), isEmpty);
    });
  });
}
