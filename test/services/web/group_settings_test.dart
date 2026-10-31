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
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/group_facade.dart';
import 'package:front_porch_ai/services/web/facade/group_member_seed.dart';
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
  // desktop's neutral seeds and member extensions.
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
      'the old body shape gets Realism and Needs on with neutral seeds',
      () async {
        final (g, ext, mid) = await made({
          'name': 'Old Phone',
          'memberIds': [plainId, carded],
          'turnOrder': 'roundRobin',
        });
        final seeds = parseGroupRealismSeeds(g.defaultMemberRealismState);
        expect(seeds.keys.toSet(), mid.values.toSet());
        for (final s in seeds.values) {
          expect(s['affection'], 35);
          expect(s['trust'], 40);
          expect(s['emotion'], 'neutral');
          expect(s['needs'], isA<Map>(), reason: 'needs on by default');
        }
        final baseline = jsonDecode(g.baselineRealismState) as Map;
        expect(baseline[mid[plainId]], containsPair('affection', 35));
        expect(baseline[mid[plainId]], containsPair('trust', 40));
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
  // test goes red; turn realism on with neutralGroupRealismBlobs instead
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
}
