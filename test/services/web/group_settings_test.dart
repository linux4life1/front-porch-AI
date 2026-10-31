// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/group_facade.dart';
import 'package:front_porch_ai/services/web/facade/group_member_seed.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook_import.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/web/facade/group_member_edit.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart'
    show legacyCardExtSeedKeys;

import '../../golden/support/fakes.dart';

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
        // The desktop wizard has no Group System Prompt (it points to Group
        // Settings after creating), so the relay no longer reads one: a
        // posted value is ignored rather than set.
        expect(g.systemPrompt, isEmpty);
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

  // Realism-step parity: the desktop wizard's Chaos, Story Calendar start,
  // per-member emotion, verification and needs land on a web-made group the
  // way GroupChatCommitter writes them, and an old phone's body (name,
  // members, turn order only) still gets Realism and Needs on with the
  // desktop's card seeds and member extensions.
  group('GroupFacade.createGroup Realism step parity', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupFacade facade;
    late String plainId; // a card with no FrontPorchExtensions
    late String carded; // a card that ships its own

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final chars = CharacterRepository(db, storage);
      await chars.addCharacter(
        CharacterCard(name: 'Plain', description: 'No extensions.'),
      );
      await chars.addCharacter(
        CharacterCard(
          name: 'Carded',
          description: 'Ships extensions.',
          frontPorchExtensions: FrontPorchExtensions(
            needsBaselineHunger: 50,
            needsPace: 'sloth',
            realismVerificationStrictness: 2,
          ),
        ),
      );
      plainId = chars.characters.firstWhere((c) => c.name == 'Plain').dbId!;
      carded = chars.characters.firstWhere((c) => c.name == 'Carded').dbId!;
      groups = GroupChatRepository(storage, db);
      facade = GroupFacade(groups, storage, chars, db);
    });

    tearDown(() => db.close());

    Future<(GroupChat, Map<String, FrontPorchExtensions?>, Map<String, String>)>
    made(Map<String, dynamic> body) async {
      final r = await facade.createGroup(body);
      await groups.reload();
      final g = groups.getById(r!['id'] as String)!;
      final members = await groups.getMembersForGroup(g.id);
      return (
        g,
        {
          for (final m in members)
            m.originLibraryDbId!: m.frontPorchExtensions == null
                ? null
                : FrontPorchExtensions.fromJson(m.frontPorchExtensions!),
        },
        {for (final m in members) m.originLibraryDbId!: m.id},
      );
    }

    test(
      'the old body shape gets Realism and Needs on, members from their cards',
      () async {
        final (g, ext, mid) = await made({
          'name': 'Old Phone',
          'memberIds': [plainId, carded],
          'turnOrder': 'roundRobin',
        });
        final seeds = parseGroupRealismSeeds(g.defaultMemberRealismState);
        expect(seeds.keys.toSet(), mid.values.toSet());
        for (final s in seeds.values) {
          expect(s['needs'], isA<Map>(), reason: 'needs on by default');
        }
        // Changed: each member starts from their card, as New Chat starts a
        // 1:1 with it, no longer at the neutral 35 / 40. Plain says nothing
        // and Carded leaves its bonds alone, so both start at the card
        // defaults; Carded keeps its own Needs.
        final baseline = jsonDecode(g.baselineRealismState) as Map;
        for (final id in [plainId, carded]) {
          final s = seeds[mid[id]]!;
          expect(
            [s['affection'], s['longTermScore'], s['trust'], s['emotion']],
            [0, 0, 0, 'neutral'],
            reason: id,
          );
          expect(baseline[mid[id]], containsPair('affection', 0));
          expect(baseline[mid[id]], containsPair('longTermScore', 0));
          expect(baseline[mid[id]], containsPair('trust', 0));
          expect(baseline[mid[id]], containsPair('emotion', 'neutral'));
        }
        expect(seeds[mid[carded]]!['needs'], containsPair('hunger', 50));
        expect(seeds[mid[carded]]!['needsPace'], 'sloth');
        expect(g.chaosModeEnabled, isFalse);
        // A card with no extensions gets the desktop committer's fresh ones.
        final plain = ext[plainId]!;
        expect(plain.realismVerificationEnabled, isFalse);
        expect(plain.realismVerificationMaxReprocesses, 1);
        expect(plain.realismVerificationStrictness, 3);
        expect(plain.needsPace, 'normal');
        expect(plain.needsBaselineHunger, 80);
        expect(plain.stableId, isNotNull);
        // A card's own extensions survive a body that says nothing of them.
        expect(ext[carded]!.needsBaselineHunger, 50);
        expect(ext[carded]!.needsPace, 'sloth');
        expect(ext[carded]!.realismVerificationStrictness, 2);
      },
    );

    test('every Realism-step field lands on the group and members', () async {
      final member = {
        'affection': 70,
        'trust': 65,
        'emotion': 'wistful',
        'emotionIntensity': 'strong',
        'verificationEnabled': true,
        'verificationMaxReprocesses': 4,
        'verificationStrictness': 5,
        'needsPace': 'fast',
        'needsOff': ['bladder'],
        'needsBaselineHunger': 10,
        'needsBaselineBladder': 20,
        'needsBaselineEnergy': 30,
        'needsBaselineSocial': 40,
        'needsBaselineFun': 50,
        'needsBaselineHygiene': 60,
        'needsBaselineComfort': 70,
        'enjoysLowHygiene': true,
      };
      final (g, ext, mid) = await made({
        'name': 'Full Porch',
        'memberIds': [plainId, carded],
        'chaosModeEnabled': true,
        'chaosNsfwEnabled': true,
        'realism': {
          'storyStartDate': '1887-06-01',
          'storyStartTime': '07:30',
          'members': {plainId: member, carded: member},
        },
      });
      expect(g.chaosModeEnabled, isTrue);
      expect(g.chaosNsfwEnabled, isTrue);
      final time = parseGroupTimeSeed(
        g.defaultMemberRealismState,
        g.baselineRealismState,
      )!;
      expect(time.storyStartDate, '1887-06-01');
      expect(time.storyStartTime, '07:30');
      final seed = parseGroupRealismSeeds(
        g.defaultMemberRealismState,
      )[mid[plainId]]!;
      expect(seed, containsPair('emotion', 'wistful'));
      expect(seed, containsPair('emotionIntensity', 'strong'));
      expect(seed, containsPair('needsBaselineComfort', 70));
      final baseline = jsonDecode(g.baselineRealismState) as Map;
      expect(baseline[mid[carded]], containsPair('emotion', 'wistful'));
      expect(baseline[mid[carded]], containsPair('emotionIntensity', 'strong'));
      for (final id in [plainId, carded]) {
        final e = ext[id]!;
        expect(e.realismVerificationEnabled, isTrue, reason: id);
        expect(e.realismVerificationMaxReprocesses, 4);
        expect(e.realismVerificationStrictness, 5);
        expect(e.needsPace, 'fast');
        expect(e.needsOff, ['bladder']);
        expect(
          [
            e.needsBaselineHunger,
            e.needsBaselineBladder,
            e.needsBaselineEnergy,
            e.needsBaselineSocial,
            e.needsBaselineFun,
            e.needsBaselineHygiene,
            e.needsBaselineComfort,
          ],
          [10, 20, 30, 40, 50, 60, 70],
        );
        expect(e.enjoysLowHygiene, isTrue);
      }
    });

    test('malformed Realism-step fields fall back to the defaults', () async {
      final (g, ext, mid) = await made({
        'name': 'Garbled',
        'memberIds': [plainId, carded],
        'chaosModeEnabled': 'yes',
        'realism': {
          'storyStartDate': 'someday',
          'storyStartTime': '25:99',
          'members': {
            plainId: {
              'emotion': '   ',
              'emotionIntensity': 'volcanic',
              'verificationEnabled': 'true',
              'verificationMaxReprocesses': 99,
              'needsPace': 'warp',
              'needsOff': ['thirst', 3, 'fun'],
              'needsBaselineHunger': '12',
            },
          },
        },
      });
      expect(g.chaosModeEnabled, isFalse);
      final time = parseGroupTimeSeed(
        g.defaultMemberRealismState,
        g.baselineRealismState,
      )!;
      expect(time.storyStartDate, isNull);
      expect(time.storyStartTime, isNull);
      final seed = parseGroupRealismSeeds(
        g.defaultMemberRealismState,
      )[mid[plainId]]!;
      expect(seed['emotion'], 'neutral');
      expect(seed['emotionIntensity'], 'mild');
      final e = ext[plainId]!;
      expect(e.realismVerificationEnabled, isFalse);
      expect(e.realismVerificationMaxReprocesses, 5, reason: 'clamped to 1-5');
      expect(e.needsPace, 'normal');
      expect(e.needsOff, ['fun']);
      expect(e.needsBaselineHunger, 80);
    });
  
    test('bond and trust take the desktop ranges, clamped there', () async {
      // Changed: Long-Term Bond has its own key (longTermScore, ±300) and
      // trust is Trust Level (±100). The old ±300 trust was Long-Term Bond
      // saved in the wrong key.
      final (g, _, mid) = await made({
        'name': 'Wide Scale',
        'memberIds': [plainId, carded],
        'realism': {
          'members': {
            plainId: {'affection': -250, 'longTermScore': 280, 'trust': 90},
            carded: {'affection': 400, 'longTermScore': -999, 'trust': -999},
          },
        },
      });
      final seeds = parseGroupRealismSeeds(g.defaultMemberRealismState);
      expect(seeds[mid[plainId]], containsPair('affection', -250));
      expect(seeds[mid[plainId]], containsPair('longTermScore', 280));
      expect(seeds[mid[plainId]], containsPair('trust', 90));
      expect(seeds[mid[carded]], containsPair('affection', 300));
      expect(seeds[mid[carded]], containsPair('longTermScore', -300));
      expect(seeds[mid[carded]], containsPair('trust', -100));
      final baseline = jsonDecode(g.baselineRealismState) as Map;
      expect(baseline[mid[plainId]], containsPair('affection', -250));
      expect(baseline[mid[plainId]], containsPair('longTermScore', 280));
      expect(baseline[mid[plainId]], containsPair('trust', 90));
    });

    test("the wizard's Afterglow switch sets how the group's chats start "
        'it; an older phone sends none and gets on', () async {
      final (off, _, _) = await made({
        'name': 'Cool Porch',
        'memberIds': [plainId, carded],
        'realism': {'afterglow': false},
      });
      expect(groupAfterglowIn(off.defaultMemberRealismState), isFalse);
      expect(
        parseGroupRealismSeeds(off.defaultMemberRealismState),
        hasLength(2),
      );

      final (old, _, _) = await made({
        'name': 'Old Phone',
        'memberIds': [plainId, carded],
      });
      expect(groupAfterglowIn(old.defaultMemberRealismState), isTrue);
    });
  });

  // The phone's new-group wizard posted Long-Term Bond into trust, as the
  // desktop card saved it. Each bond now has its own key and scale.
  group('memberSeedOverrides bonds', () {
    test('Long-Term Bond rides longTermScore and Trust Level stays on its '
        'own scale', () {
      final out = memberSeedOverrides({
        'c1': {'affection': 70, 'longTermScore': 250, 'trust': 60},
      }, 'c1');
      expect(out, containsPair('longTermScore', 250));
      expect(out, containsPair('trust', 60));
    });

    test('a number past ±100 posted as trust by an older phone app is read '
        'as Long-Term Bond', () {
      final out = memberSeedOverrides({
        'c1': {'trust': 250},
      }, 'c1');
      expect(out, containsPair('longTermScore', 250));
      expect(out.containsKey('trust'), isFalse);
    });

    test('with longTermScore posted, trust is held to ±100', () {
      final out = memberSeedOverrides({
        'c1': {'longTermScore': 20, 'trust': 250},
      }, 'c1');
      expect(out['longTermScore'], 20);
      expect(out['trust'], 100);
    });
  });

  // Web Group Settings' "New chats" section: the twin of Edit Group's notice
  // for a group made from a 1:1 before forks saved that chat's settings, and
  // the Realism, Needs and Inherit switches for new chats. Proven to fail:
  // drop the useForkSource branch from GroupNewChats.update and the second
  // test goes red; turn realism on with a neutral seed per member instead
  // of switchGroupTemplateRealism and the third does; drop hostName from
  // findForkedGroupSource and the first does.
  group('GroupFacade.newChats', () {
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
      await groups.save(GroupChat(id: 'g1', name: 'Juniper & Wren'));
      for (final (id, name) in [('mem-j', 'Juniper'), ('mem-w', 'Wren')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(id: id, groupId: 'g1', name: name),
        );
      }
      facade = GroupFacade(groups, storage, null, db);
    });

    tearDown(() => db.close());

    // A 1:1 with Juniper, realism and needs on, whose first group chat is
    // g1's: what forkToGroupChat left before it saved honest settings.
    Future<void> forkedFromJuniper() async {
      await db
          .into(db.characters)
          .insert(CharactersCompanion.insert(id: 'char-j', name: 'Juniper'));
      await db.insertSession(
        SessionsCompanion.insert(id: 'one', characterId: const Value('char-j')),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'forked',
          groupId: const Value('g1'),
          parentSession: const Value('one'),
          realismEnabled: const Value(true),
          needsSimEnabled: const Value(true),
        ),
      );
    }

    test("the new-chats state carries Porch Life's Needs, so the phone "
        'greys the group\'s Needs switch', () async {
      expect((await facade.newChats.stateOf('g1'))!['needsAllowed'], isTrue);
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      await storage.realismSettings.setNeedsSimDefault(false);
      final off = GroupFacade(groups, storage, null, db);
      expect((await off.newChats.stateOf('g1'))!['needsAllowed'], isFalse);
    });

    test(
      'a blank group forked from a 1:1 names the chat it came from',
      () async {
        await forkedFromJuniper();
        final state = (await facade.newChats.stateOf('g1'))!;
        expect(state['realism'], isFalse);
        final source = state['forkSource'] as Map<String, dynamic>;
        expect(source['hostName'], 'Juniper');
        expect(source['realismMissing'], isTrue);
        expect(source['needsOn'], isTrue);
        expect(
          groups.getById('g1')!.defaultMemberRealismState,
          '{}',
          reason: 'reading the notice writes nothing',
        );
      },
    );

    test('"Use the chat\'s settings" saves realism and needs for every '
        'member, and the notice goes', () async {
      await forkedFromJuniper();
      expect(
        await facade.newChats.update('g1', {'useForkSource': true}),
        isTrue,
      );
      final g = groups.getById('g1')!;
      final seeds = parseGroupRealismSeeds(g.defaultMemberRealismState);
      expect(seeds.keys, unorderedEquals(['mem-j', 'mem-w']));
      expect(seeds['mem-w']!['needs'], isA<Map>());
      expect(
        g.inheritCharacterLorebooks,
        isFalse,
        reason:
            'Inherit reaches open chats, so only its own switch '
            'turns it on',
      );
      final state = (await facade.newChats.stateOf('g1'))!;
      expect(state['realism'], isTrue);
      expect(state['needs'], isTrue);
      expect(state['forkSource'], isNull);
    });

    test('Needs off keeps every seed and the scene time; Realism off keeps '
        'the greetings', () async {
      final g = groups.getById('g1')!;
      final on = buildGroupRealismBlobs(
        seeds: {
          'mem-j': {...defaultGroupMemberRealismSeed(), 'affection': 70},
        },
        needsEnabled: true,
        timeOfDay: 'evening',
        dayCount: 3,
        alternateGreetings: const ['Rain on the porch.'],
      );
      g.defaultMemberRealismState = on.defaultMemberJson;
      g.baselineRealismState = on.baselineJson;
      g.alternateGreetings = ['Rain on the porch.'];
      await groups.save(g);

      await facade.newChats.update('g1', {'needs': false});
      var saved = groups.getById('g1')!;
      final seeds = parseGroupRealismSeeds(saved.defaultMemberRealismState);
      expect(
        seeds.keys,
        unorderedEquals(['mem-j', 'mem-w']),
        reason: 'a member with no seed gets a neutral one',
      );
      expect(seeds.values.every((s) => s['needs'] == null), isTrue);
      expect(
        seeds['mem-j']!['affection'],
        70,
        reason: 'switching Needs keeps the member\'s stored seed',
      );
      expect(
        parseGroupTimeSeed(
          saved.defaultMemberRealismState,
          saved.baselineRealismState,
        )?.timeOfDay,
        'evening',
      );
      final state = (await facade.newChats.stateOf('g1'))!;
      expect(state['realism'], isTrue);
      expect(state['needs'], isFalse);

      await facade.newChats.update('g1', {'realism': false});
      saved = groups.getById('g1')!;
      expect(parseGroupRealismSeeds(saved.defaultMemberRealismState), isEmpty);
      expect(parseGroupAlternateGreetings(saved.defaultMemberRealismState), [
        'Rain on the porch.',
      ]);

      await facade.newChats.update('g1', {'inherit': true});
      expect(groups.getById('g1')!.inheritCharacterLorebooks, isTrue);
    });

    test("Afterglow for new chats is read and saved, and switching Needs "
        'keeps it', () async {
      final g = groups.getById('g1')!;
      final on = buildGroupRealismBlobs(
        seeds: {'mem-j': defaultGroupMemberRealismSeed()},
        needsEnabled: true,
        timeOfDay: 'evening',
        dayCount: 3,
      );
      g.defaultMemberRealismState = on.defaultMemberJson;
      g.baselineRealismState = on.baselineJson;
      await groups.save(g);
      expect((await facade.newChats.stateOf('g1'))!['afterglow'], isTrue);

      await facade.newChats.update('g1', {'afterglow': false});
      final saved = groups.getById('g1')!;
      expect(groupAfterglowIn(saved.defaultMemberRealismState), isFalse);
      expect(parseGroupRealismSeeds(saved.defaultMemberRealismState).keys, [
        'mem-j',
      ]);
      expect((await facade.newChats.stateOf('g1'))!['afterglow'], isFalse);

      await facade.newChats.update('g1', {'needs': false});
      expect((await facade.newChats.stateOf('g1'))!['afterglow'], isFalse);
    });
  });

  // The phone's new-group wizard posts each member's Voice pick; the relay
  // writes it on the member's row with the desktop's rule and never on the
  // library card.
  group('GroupFacade.createGroup member voices', () {
    test('a pick, the global voice and no pick each land as the desktop '
        'wizard writes them', () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_voice_root_').path,
      );
      final chars = CharacterRepository(db, storage);
      for (final (name, voice) in [
        ('Voiced', 'af_sky'),
        ('Plain', null),
        ('Third', 'af_bella'),
        ('Spaced', 'af_nova'),
      ]) {
        await chars.addCharacter(
          CharacterCard(name: name, description: 'x')..ttsVoice = voice,
        );
      }
      String id(String name) =>
          chars.characters.firstWhere((c) => c.name == name).dbId!;
      final groups = GroupChatRepository(storage, db);
      final facade = GroupFacade(groups, storage, chars, db);

      final made = await facade.createGroup({
        'name': 'Voices',
        'memberIds': [id('Voiced'), id('Plain'), id('Third'), id('Spaced')],
        // Trimmed on the way in: whitespace alone is the global voice too.
        'memberVoices': {
          id('Voiced'): '',
          id('Plain'): ' am_adam ',
          id('Spaced'): '  ',
        },
      });

      final members = await groups.getMembersForGroup(made!['id'] as String);
      expect(
        {for (final m in members) m.name: m.ttsVoice},
        {
          'Voiced': null,
          'Plain': 'am_adam',
          'Third': 'af_bella',
          'Spaced': null,
        },
      );
      expect(
        chars.characters.firstWhere((c) => c.name == 'Voiced').ttsVoice,
        'af_sky',
        reason: 'a pick never reaches the library card',
      );
    });
  });

  // A member's own Afterglow switch is theirs in the group, so a member joins
  // with it on: the card's switch says how new 1:1 chats start.
  group('GroupFacade.createGroup: each member joins with Afterglow on', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupFacade facade;
    late String shyId;
    late String plainId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      final chars = CharacterRepository(db, storage);
      await chars.addCharacter(
        CharacterCard(
          name: 'Shy',
          description: 'Starts new chats without Afterglow.',
          frontPorchExtensions: FrontPorchExtensions(afterglowEnabled: false),
        ),
      );
      await chars.addCharacter(
        CharacterCard(name: 'Plain', description: 'No extensions.'),
      );
      shyId = chars.characters.firstWhere((c) => c.name == 'Shy').dbId!;
      plainId = chars.characters.firstWhere((c) => c.name == 'Plain').dbId!;
      groups = GroupChatRepository(storage, db);
      facade = GroupFacade(groups, storage, chars, db);
    });

    tearDown(() => db.close());

    test('a member whose card starts new chats without it joins with their '
        'own switch on', () async {
      final r = await facade.createGroup({
        'name': 'Quiet Porch',
        'memberIds': [shyId, plainId],
      });
      final members = await groups.getMembersForGroup(r!['id'] as String);
      final shy = members.firstWhere((m) => m.originLibraryDbId == shyId);
      expect(
        FrontPorchExtensions.fromJson(
          shy.frontPorchExtensions!,
        ).afterglowEnabled,
        isTrue,
      );
    });
  });

  // The web member editor, the desktop member editor's twin: a member's
  // edit saves to their own row, and with the group open it edits the chat's
  // copy and sets a changed Afterglow through the chat.
  group('GroupMemberEdit', () {
    late AppDatabase db;
    late StorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      await db.insertGroup(GroupsCompanion.insert(id: 'g1', name: 'Pair'));
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-mara',
          groupId: 'g1',
          name: 'Mara',
          description: const Value('Keeps the lighthouse.'),
        ),
      );
    });

    tearDown(() => db.close());

    Future<GroupMemberRow> row() async =>
        (await db.getGroupMembers('g1')).single;

    test("a closed group's member saves to their own row", () async {
      final edit = GroupMemberEdit(db, storage, null, null);
      final before = await edit.detail('g1', 'mem-mara');
      expect(before?['groupName'], 'Pair', reason: "the page's banner");
      expect(before?['description'], 'Keeps the lighthouse.');

      expect(
        await edit.update('g1', 'mem-mara', {
          'description': 'Keeps the lamp.',
          'afterglowEnabled': false,
        }),
        isTrue,
      );

      final saved = await row();
      expect(saved.description, 'Keeps the lamp.');
      expect(
        FrontPorchExtensions.fromJson(
          jsonDecode(saved.frontPorchExtensions!) as Map<String, dynamic>,
        ).afterglowEnabled,
        isFalse,
      );
      expect(await edit.detail('g1', 'mem-nobody'), isNull);
      expect(await edit.update('g1', 'mem-nobody', const {}), isFalse);
    });

    test("an open group's member is edited on the chat's own copy, and a "
        'changed Afterglow is set through the chat', () async {
      final live =
          CharacterCard(name: 'Mara', description: 'Keeps the lighthouse.')
            ..dbId = 'mem-mara'
            ..frontPorchExtensions = FrontPorchExtensions();
      final chat = _OpenPair([live]);
      addTearDown(chat.dispose);
      final edit = GroupMemberEdit(db, storage, chat, null);

      expect(
        await edit.update('g1', 'mem-mara', {
          'description': 'Keeps the lamp.',
          'afterglowEnabled': false,
        }),
        isTrue,
      );

      expect(
        live.description,
        'Keeps the lamp.',
        reason: "the chat's copy, so its next save cannot put the old back",
      );
      expect(chat.refreshed, [same(live)]);
      expect(
        chat.afterglowSets,
        hasLength(1),
        reason: 'the chat clears her Lust only when it sets the switch',
      );
      expect(chat.afterglowSets.single.$1, same(live));
      expect(chat.afterglowSets.single.$2, isFalse);
      expect((await row()).description, 'Keeps the lamp.');
    });

    test('a save keeps extensions the app could not read, in the row and '
        "in the open chat's copy", () async {
      // Imported from a foreign group card: a whole number stored as a
      // decimal. The member loads with no extensions; the web page still
      // posts every Realism field.
      const foreign = '{"realism_engine":{"day_count":2.0}}';
      await db.updateGroupMember(
        const GroupMembersCompanion(
          id: Value('mem-mara'),
          frontPorchExtensions: Value(foreign),
        ),
      );
      final live = CharacterCard(name: 'Mara')..dbId = 'mem-mara';
      final chat = _OpenPair([live]);
      addTearDown(chat.dispose);

      expect(
        await GroupMemberEdit(
          db,
          storage,
          chat,
          null,
        ).update('g1', 'mem-mara', {
          'description': 'Keeps the lamp.',
          'realismEnabled': true,
          'afterglowEnabled': true,
        }),
        isTrue,
      );

      final saved = await row();
      expect(saved.description, 'Keeps the lamp.');
      expect(saved.frontPorchExtensions, foreign);
      expect(
        live.frontPorchExtensions,
        isNull,
        reason: "the chat's copy would write the defaults on its next save",
      );
    });
  });

  // A web-made group's members started at the neutral seed (bond 35, trust
  // 40, neutral mood, every bar at the neutral needs), whatever their card
  // said. Each member now starts from their card, as New Chat starts a 1:1
  // with that card, with what the phone wizard set laid over it. Turning
  // Realism for new chats on later starts a member with no seed the same
  // way and leaves saved seeds as they are.
  group('GroupFacade.createGroup: members start from their cards', () {
    late AppDatabase db;
    late GroupChatRepository groups;
    late GroupFacade facade;
    late CharacterRepository chars;
    late String waryId;
    late String plainId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      final storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      chars = CharacterRepository(db, storage);
      await chars.addCharacter(
        CharacterCard(
          name: 'Wary',
          description: 'Starts guarded.',
          frontPorchExtensions: FrontPorchExtensions(
            shortTermBond: -60,
            longTermBond: 140,
            trustLevel: -25,
            characterEmotion: 'guarded',
            emotionIntensity: 'strong',
            needsBaselineHunger: 30,
            needsBaselineFun: 55,
            needsPace: 'fast',
            needsOff: ['bladder'],
            enjoysLowHygiene: true,
            realismVerificationEnabled: true,
            realismVerificationMaxReprocesses: 4,
            realismNeedsDirectorAuthority: true,
          ),
        ),
      );
      await chars.addCharacter(
        CharacterCard(name: 'Plain', description: 'No extensions.'),
      );
      waryId = chars.characters.firstWhere((c) => c.name == 'Wary').dbId!;
      plainId = chars.characters.firstWhere((c) => c.name == 'Plain').dbId!;
      groups = GroupChatRepository(storage, db);
      facade = GroupFacade(groups, storage, chars, db);
    });

    tearDown(() => db.close());

    Future<(GroupChat, Map<String, String>)> made(
      Map<String, dynamic> body,
    ) async {
      final r = await facade.createGroup({
        'name': 'Porch',
        'memberIds': [waryId, plainId],
        ...body,
      });
      await groups.reload();
      final g = groups.getById(r!['id'] as String)!;
      final members = await groups.getMembersForGroup(g.id);
      return (g, {for (final m in members) m.originLibraryDbId!: m.id});
    }

    test('a member the wizard left alone starts at their card\'s bonds, '
        'mood and Needs bars', () async {
      final (g, mid) = await made({});
      final members = await groups.getMembersForGroup(g.id);
      final wary = parseGroupRealismSeeds(
        g.defaultMemberRealismState,
      )[mid[waryId]]!;
      expect(
        [
          wary['affection'],
          wary['longTermScore'],
          wary['trust'],
          wary['emotion'],
          wary['emotionIntensity'],
        ],
        [-60, 140, -25, 'guarded', 'strong'],
        reason: 'THE BUG: the neutral 35 / 40 / neutral won over the card',
      );
      expect(wary['needs'], containsPair('hunger', 30));
      expect(wary['needs'], containsPair('fun', 55));
      expect(wary['needs'], containsPair('energy', 80));
      final baseline = jsonDecode(g.baselineRealismState) as Map;
      expect(baseline[mid[waryId]], containsPair('affection', -60));
      expect(baseline[mid[waryId]], containsPair('longTermScore', 140));
      expect(baseline[mid[waryId]], containsPair('trust', -25));

      final plain = parseGroupRealismSeeds(
        g.defaultMemberRealismState,
      )[mid[plainId]]!;
      expect(
        [
          plain['affection'],
          plain['longTermScore'],
          plain['trust'],
          plain['emotion'],
        ],
        [0, 0, 0, 'neutral'],
        reason: 'a card that says nothing starts where a 1:1 with it does',
      );
      expect(plain['needs'], containsPair('social', 80));

      final row = FrontPorchExtensions.fromJson(
        members.firstWhere((m) => m.id == mid[waryId]).frontPorchExtensions!,
      );
      expect(row.needsPace, 'fast');
      expect(row.needsOff, ['bladder']);
      expect(row.enjoysLowHygiene, isTrue);
      expect(row.realismVerificationEnabled, isTrue);
      expect(row.realismVerificationMaxReprocesses, 4);
      expect(row.realismNeedsDirectorAuthority, isTrue);
    });

    test('what the wizard set wins over the card, and a moved baseline '
        'starts its bar there', () async {
      final (g, mid) = await made({
        'realism': {
          'members': {
            waryId: {'affection': 90, 'emotion': 'fond'},
            plainId: {'needsBaselineHunger': 40},
          },
        },
      });
      final seeds = parseGroupRealismSeeds(g.defaultMemberRealismState);
      final wary = seeds[mid[waryId]]!;
      expect(wary['affection'], 90);
      expect(wary['emotion'], 'fond');
      expect(wary['trust'], -25, reason: 'not posted, so the card stands');
      final plain = seeds[mid[plainId]]!;
      expect(plain['needsBaselineHunger'], 40);
      expect(
        plain['needs'],
        containsPair('hunger', 40),
        reason: 'THE BUG: the bar stayed where it started',
      );
      expect(plain['needs'], containsPair('social', 80));

      final card = chars.characters.firstWhere((c) => c.dbId == waryId);
      expect(
        (
          card.frontPorchExtensions!.shortTermBond,
          card.frontPorchExtensions!.characterEmotion,
        ),
        (-60, 'guarded'),
        reason: 'a group never writes the library card',
      );
    });

    // What the phone posts for High Bond (membersAtPreset): Long-Term Bond
    // with Short-Term Bond, so the saved seed is what the slider showed.
    test('a posted preset saves its Long-Term Bond over the card\'s', () async {
      final (g, mid) = await made({
        'realism': {
          'members': {
            waryId: {
              'affection': 75,
              'longTermScore': 75,
              'trust': 70,
              'emotion': 'affection',
              'emotionIntensity': 'moderate',
            },
          },
        },
      });
      final wary = parseGroupRealismSeeds(
        g.defaultMemberRealismState,
      )[mid[waryId]]!;
      expect(
        [wary['affection'], wary['longTermScore'], wary['trust']],
        [75, 75, 70],
      );
      expect(wary['needsPace'], 'fast', reason: 'the card Needs stay');
      final baseline = jsonDecode(g.baselineRealismState) as Map;
      expect(baseline[mid[waryId]], containsPair('longTermScore', 75));
    });

    test('Realism for new chats coming on starts each member from their '
        'card', () async {
      final (g, mid) = await made({
        'realism': {'enabled': false},
      });
      expect(parseGroupRealismSeeds(g.defaultMemberRealismState), isEmpty);
      expect(await facade.newChats.update(g.id, {'realism': true}), isTrue);
      final seeds = parseGroupRealismSeeds(
        groups.getById(g.id)!.defaultMemberRealismState,
      );
      expect(
        [
          seeds[mid[waryId]]!['affection'],
          seeds[mid[waryId]]!['longTermScore'],
          seeds[mid[waryId]]!['trust'],
          seeds[mid[waryId]]!['emotion'],
        ],
        [-60, 140, -25, 'guarded'],
        reason: 'THE BUG: a member with no seed came on at 35 / 40',
      );
      expect(seeds[mid[waryId]]!['needs'], containsPair('hunger', 30));
      expect(seeds[mid[plainId]]!['affection'], 0);
    });

    test('a member who already has a seed keeps it when Realism or Needs '
        'for new chats is switched', () async {
      final (g, mid) = await made({
        'realism': {'needsEnabled': false},
      });
      final saved = parseGroupRealismSeeds(g.defaultMemberRealismState);
      final kept = {...saved[mid[waryId]]!, 'affection': 5};
      g.defaultMemberRealismState = buildGroupRealismBlobs(
        seeds: {mid[waryId]!: kept},
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      ).defaultMemberJson;
      await groups.save(g);

      expect(await facade.newChats.update(g.id, {'needs': true}), isTrue);
      final seeds = parseGroupRealismSeeds(
        groups.getById(g.id)!.defaultMemberRealismState,
      );
      expect(seeds[mid[waryId]]!['affection'], 5, reason: 'its saved seed');
      expect(
        seeds[mid[waryId]]!['needs'],
        containsPair('hunger', 30),
        reason: 'Needs coming on gives its card\'s starting bars',
      );
      expect(
        seeds[mid[plainId]]!['affection'],
        0,
        reason: 'the member with no seed starts from their card',
      );
    });
  });

  // The web member editor shows the group's own switches read-only, and the
  // member's start in the group's new chats (`groupStart`) saves to the
  // group's seed for them, never to their card.
  group("GroupMemberEdit: the member's group and start", () {
    late AppDatabase db;
    late StorageService storage;
    final blobs = buildGroupRealismBlobs(
      seeds: {'mem-mara': defaultGroupMemberRealismSeed()},
      needsEnabled: true,
      timeOfDay: 'evening',
      dayCount: 3,
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.setRootPath(
        Directory.systemTemp.createTempSync('fpai_root_').path,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'g1',
          name: 'Pair',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
          chaosModeEnabled: const Value(true),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-mara',
          groupId: 'g1',
          name: 'Mara',
        ),
      );
    });

    tearDown(() => db.close());

    test("a closed group's detail carries its settings for new chats and "
        'where she starts', () async {
      final d = (await GroupMemberEdit(
        db,
        storage,
        null,
        null,
      ).detail('g1', 'mem-mara'))!;
      final group = d['group'] as Map<String, dynamic>;
      expect(
        [group['realism'], group['needs'], group['chaos'], group['timeLabel']],
        [true, true, true, 'Evening, Day 3'],
      );
      expect(d['start'], {
        'shortTermBond': 35,
        'longTermBond': 35,
        'trustLevel': 40,
        'characterEmotion': 'neutral',
        'emotionIntensity': 'mild',
      });
      expect(d['lite'], isFalse);
    });

    test("a posted groupStart saves to the group's seed for her, Long-Term "
        "Bond under its own key, and never to her card", () async {
      final edit = GroupMemberEdit(db, storage, null, null);
      expect(
        await edit.update('g1', 'mem-mara', {
          'groupStart': {'longTermBond': 120, 'trustLevel': 'lots'},
        }),
        isTrue,
      );

      final g = (await db.getGroupById('g1'))!;
      final seed = parseGroupRealismSeeds(
        g.defaultMemberRealismState,
      )['mem-mara']!;
      expect(
        (seed['affection'], seed['longTermScore'], seed['trust']),
        (35, 120, 40),
        reason: 'a field left out, or of the wrong type, keeps its value',
      );
      expect(
        ((jsonDecode(g.baselineRealismState) as Map)['mem-mara']
            as Map)['longTermScore'],
        120,
      );
      final raw = (await db.getGroupMembers('g1')).single.frontPorchExtensions;
      final ext = raw == null
          ? null
          : FrontPorchExtensions.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            );
      expect(ext?.longTermBond, isNot(120), reason: "never her card's bond");
    });

    test('a group whose new chats start without Realism has no start and '
        'takes none', () async {
      await db.updateGroup(
        const GroupsCompanion(
          id: Value('g1'),
          defaultMemberRealismState: Value('{}'),
          baselineRealismState: Value('{}'),
        ),
      );
      final edit = GroupMemberEdit(db, storage, null, null);
      expect((await edit.detail('g1', 'mem-mara'))!['start'], isNull);
      await edit.update('g1', 'mem-mara', {
        'groupStart': {'shortTermBond': 90},
      });
      expect(
        (await db.getGroupById('g1'))!.defaultMemberRealismState,
        '{}',
        reason: 'a seed written here would switch Realism on for the group',
      );
    });

    test("Group Settings' summaries say where each member starts", () async {
      final rows = (await GroupMemberEdit(
        db,
        storage,
        null,
        null,
      ).summaries('g1'))!;
      expect(rows.single['id'], 'mem-mara');
      expect((rows.single['start'] as Map)['trustLevel'], 40);
      expect(
        rows.single['afterglow'],
        isNull,
        reason: 'Porch Life keeps Afterglow off',
      );
      expect(
        await GroupMemberEdit(db, storage, null, null).summaries('nope'),
        isNull,
      );
    });

    test("a member with no seed posting her start leaves the group's Needs "
        'off for new chats', () async {
      final needsOff = buildGroupRealismBlobs(
        seeds: {'mem-bo': defaultGroupMemberRealismSeed()},
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.updateGroup(
        GroupsCompanion(
          id: const Value('g1'),
          defaultMemberRealismState: Value(needsOff.defaultMemberJson),
          baselineRealismState: Value(needsOff.baselineJson),
        ),
      );
      await GroupMemberEdit(db, storage, null, null).update('g1', 'mem-mara', {
        'groupStart': {'trustLevel': 70},
      });

      final stored = (await db.getGroupById('g1'))!.defaultMemberRealismState;
      expect(parseGroupRealismSeeds(stored)['mem-mara']!['trust'], 70);
      expect(groupTemplateRealismOf(stored).needsOn, isFalse);
    });

    test("a seed an older group filed under the member's origin is the start "
        'the phone shows and saves', () async {
      await db.updateGroupMember(
        GroupMembersCompanion(
          id: const Value('mem-mara'),
          memberState: Value(
            GroupMember.encodeProvenance(originStableId: 'mara-origin'),
          ),
        ),
      );
      final legacy = buildGroupRealismBlobs(
        seeds: {
          'mara-origin': {...defaultGroupMemberRealismSeed(), 'affection': 90},
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.updateGroup(
        GroupsCompanion(
          id: const Value('g1'),
          defaultMemberRealismState: Value(legacy.defaultMemberJson),
          baselineRealismState: Value(legacy.baselineJson),
        ),
      );
      final edit = GroupMemberEdit(db, storage, null, null);
      final start = (await edit.detail('g1', 'mem-mara'))!['start'] as Map;
      expect(start['shortTermBond'], 90);
      await edit.update('g1', 'mem-mara', {
        'groupStart': {'trustLevel': 30},
      });
      final seeds = parseGroupRealismSeeds(
        (await db.getGroupById('g1'))!.defaultMemberRealismState,
      );
      expect(seeds.keys, ['mem-mara']);
      expect(
        [seeds['mem-mara']!['affection'], seeds['mem-mara']!['trust']],
        [90, 30],
      );
    });

    // A group whose only member entries carry no bonds runs Realism in New
    // Chat, as every reader of the blob has it, so the phone offers and
    // saves a start there too.
    for (final (shape, entry) in [
      ('a Group Settings preference', {'enjoysLowHygiene': true}),
      (
        "an older editor's keys",
        {'shortTermBond': 80, 'trustLevel': 20, 'characterEmotion': 'shy'},
      ),
    ]) {
      test('a group whose only member entry is $shape offers and saves a '
          'start', () async {
        await db.updateGroup(
          GroupsCompanion(
            id: const Value('g1'),
            defaultMemberRealismState: Value(
              jsonEncode({
                'perChar': {'mem-mara': entry},
              }),
            ),
            baselineRealismState: const Value('{}'),
          ),
        );
        final edit = GroupMemberEdit(db, storage, null, null);
        final d = (await edit.detail('g1', 'mem-mara'))!;
        expect(d['start'], isNotNull);
        expect((d['group'] as Map)['realism'], isTrue);
        await edit.update('g1', 'mem-mara', {
          'groupStart': {'trustLevel': 70},
        });
        final seed = parseGroupRealismSeeds(
          (await db.getGroupById('g1'))!.defaultMemberRealismState,
        )['mem-mara']!;
        expect(seed['trust'], 70);
        for (final k in entry.keys) {
          if (!legacyCardExtSeedKeys.contains(k)) {
            expect(seed[k], entry[k], reason: '$k is kept');
          }
        }
      });
    }

    test("an open group's start on the phone comes from its row, not the "
        "chat's copy", () async {
      final chat = _OpenPair([CharacterCard(name: 'Mara')..dbId = 'mem-mara']);
      addTearDown(chat.dispose);
      // The chat's copy says no member entries; the row has Mara's seed.
      final d = (await GroupMemberEdit(
        db,
        storage,
        chat,
        null,
      ).detail('g1', 'mem-mara'))!;
      expect((d['start'] as Map)['trustLevel'], 40);
      expect((d['group'] as Map)['realism'], isTrue);
    });

    test("the detail carries Porch Life's Realism permission", () async {
      final edit = GroupMemberEdit(db, storage, null, null);
      expect((await edit.detail('g1', 'mem-mara'))!['realismAllowed'], isTrue);
      await storage.realismSettings.setRealismAllowed(false);
      expect(
        (await edit.detail('g1', 'mem-mara'))!['realismAllowed'],
        isFalse,
        reason: 'the phone hides her Realism, Needs and Afterglow',
      );
    });
  });
}

/// Group g1 ("Pair") open in the chat on [members]. Like ChatService's, its
/// member Afterglow setter does nothing when the card already holds [on].
class _OpenPair extends FakeChatService {
  _OpenPair(this.members);

  final List<CharacterCard> members;
  final refreshed = <CharacterCard>[];
  final afterglowSets = <(CharacterCard, bool)>[];

  @override
  bool get isGroupMode => true;

  @override
  GroupChat? get activeGroup => GroupChat(id: 'g1', name: 'Pair');

  @override
  List<CharacterCard> get groupCharacters => members;

  @override
  void refreshActiveCharacterCard(CharacterCard card) => refreshed.add(card);

  @override
  Future<void> setMemberAfterglowEnabled(CharacterCard member, bool on) async {
    if ((member.frontPorchExtensions?.afterglowEnabled ?? true) == on) return;
    afterglowSets.add((member, on));
    member.frontPorchExtensions =
        (member.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
          afterglowEnabled: on,
        );
  }
}
