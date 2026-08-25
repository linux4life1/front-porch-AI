// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Selecting an angry alt must apply that alt's authored opening, and
// swiping back to first_mes must restore the card seed. Proven red: before
// _applyGreetingOpeningSeed, selectGreeting only swapped text and either
// kept the friend seed or overwrote it with reading-the-room, never restored.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// Delayed eval payload that would stomp first_mes if a stale future applied.
class _DelayedStompLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield '{"emotion":"ecstatic","emotion_intensity":"strong"}';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'DelayedStompLlm';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_greet_seed_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db)
      ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<CharacterCard> openFresh() async {
    await db.insertCharacter(
      CharactersCompanion.insert(
        id: 'char-a',
        name: 'Nemu',
        imagePath: const Value('/tmp/Nemu_1.png'),
        firstMessage: const Value('Hello, friend.'),
        alternateGreetings: const Value('["Get out."]'),
      ),
    );
    final card = CharacterCard(
      name: 'Nemu',
      imagePath: '/tmp/Nemu_1.png',
      firstMessage: 'Hello, friend.',
      alternateGreetings: const ['Get out.'],
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        characterEmotion: 'warm',
        emotionIntensity: 'mild',
        shortTermBond: 20,
        trustLevel: 10,
        timeOfDay: 'morning',
        needsSimEnabled: true,
        needsBaselineHunger: 80,
        greetingSeeds: [
          GreetingRealismSeed(
            characterEmotion: 'furious',
            emotionIntensity: 'strong',
            shortTermBond: -40,
            trustLevel: -25,
            timeOfDay: 'night',
            needsBaselineHunger: 25,
          ),
        ],
      ),
    )..dbId = 'char-a';
    await chat.setActiveCharacter(card);
    return card;
  }

  test(
    'first_mes keeps the card seed; angry alt applies overlay; back restores',
    () async {
      await openFresh();

      expect(chat.messages, isNotEmpty);
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
      expect(chat.greetingIndex, 0);

      await chat.selectGreeting(1);

      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(chat.characterEmotion, 'furious');
      expect(chat.relationshipService.affectionScore, -40);
      expect(chat.relationshipService.trustLevel, -25);
      expect(chat.timeService.timeOfDay, 'night');
      expect(chat.needsSimulation.vector['hunger'], 25);
      expect(chat.messages.first.activeMetadata?[kGreetingIndexMetadataKey], 1);

      await chat.selectGreeting(0);

      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
    },
  );

  test('reload recovers the greeting cursor from stamped metadata', () async {
    final card = await openFresh();
    await chat.selectGreeting(1);
    final sessionId = chat.currentSessionId!;

    await chat.loadSession(sessionId);
    // setActiveCharacter already ran; loadSession rehydrates the same card.
    expect(chat.greetingIndex, 1, reason: 'cursor must survive reload');
    expect(chat.messages.first.text, 'Get out.');
    expect(
      chat.characterEmotion,
      'furious',
      reason: 'overlay emotion must survive reload, not first_mes friend',
    );
    expect(chat.relationshipService.affectionScore, -40);
    expect(chat.relationshipService.trustLevel, -25);
    expect(chat.timeService.timeOfDay, 'night');
    expect(chat.needsSimulation.vector['hunger'], 25);

    // A second ChatService on the same DB (app restart) uses the same card.
    expect(card.alternateGreetings, isNotEmpty);
  });

  test(
    'group custom opener cycles alts and fans the seed to every member',
    () async {
      final angry = GreetingRealismSeed(
        characterEmotion: 'furious',
        emotionIntensity: 'strong',
        shortTermBond: -40,
        timeOfDay: 'night',
      );
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-a': defaultGroupMemberRealismSeed(),
          'mem-b': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
        alternateGreetings: const ['Get out of my house.'],
        greetingSeeds: [angry],
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-greet',
          name: 'The House',
          firstMessage: const Value('Come in, friends.'),
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in [('mem-a', 'Ana'), ('mem-b', 'Bea')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.$1,
            groupId: 'grp-greet',
            name: m.$2,
            firstMessage: const Value('Hi.'),
          ),
        );
      }
      final group = GroupChat(
        id: 'grp-greet',
        name: 'The House',
        firstMessage: 'Come in, friends.',
        alternateGreetings: const ['Get out of my house.'],
        greetingSeeds: [angry],
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.openingAllGreetings, hasLength(2));
      expect(chat.isSelectableGreeting(0), isTrue);
      expect(chat.messages.first.text, 'Come in, friends.');
      expect(chat.timeService.timeOfDay, 'morning');

      await chat.selectGreeting(1);

      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out of my house.');
      expect(chat.timeService.timeOfDay, 'night');
      expect(chat.characterEmotion, 'furious');
    },
  );

  Pockets? livePockets() {
    final c = chat.activeCharacter;
    if (c == null) return null;
    return chat.pocketsFor(chat.characterIdFor(c));
  }

  test(
    'angry alt overlays wardrobe; swipe 0 restores the card outfit',
    () async {
      final cardOutfit = Pockets.cardJsonFrom(
        worn: const ['flour-dusted apron (well-worn)'],
        carrying: const ['shop keys'],
      );
      final altOutfit = Pockets.cardJsonFrom(
        worn: const ['rain-soaked coat'],
        carrying: const ['house keys'],
      );
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-wardrobe',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_w.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      final card = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_w.png',
        firstMessage: 'Hello, friend.',
        alternateGreetings: const ['Get out.'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'warm',
          emotionIntensity: 'mild',
          shortTermBond: 20,
          trustLevel: 10,
          timeOfDay: 'morning',
          needsSimEnabled: true,
          needsBaselineHunger: 80,
          inventory: cardOutfit,
          greetingSeeds: [
            GreetingRealismSeed(
              characterEmotion: 'furious',
              emotionIntensity: 'strong',
              shortTermBond: -40,
              trustLevel: -25,
              timeOfDay: 'night',
              needsBaselineHunger: 25,
              inventory: altOutfit,
            ),
          ],
        ),
      )..dbId = 'char-wardrobe';
      await chat.setActiveCharacter(card);

      expect(chat.characterEmotion, 'warm');
      expect(
        livePockets()!.worn.map((i) => i.name),
        contains('flour-dusted apron'),
      );
      expect(livePockets()!.carrying.map((i) => i.name), contains('shop keys'));

      await chat.selectGreeting(1);

      expect(chat.characterEmotion, 'furious');
      expect(chat.relationshipService.affectionScore, -40);
      expect(chat.needsSimulation.vector['hunger'], 25);
      expect(chat.timeService.timeOfDay, 'night');
      expect(
        livePockets()!.worn.map((i) => i.name),
        contains('rain-soaked coat'),
      );
      expect(
        livePockets()!.carrying.map((i) => i.name),
        contains('house keys'),
      );
      expect(
        livePockets()!.worn.map((i) => i.name),
        isNot(contains('flour-dusted apron')),
      );

      await chat.selectGreeting(0);

      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.needsSimulation.vector['hunger'], 80);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(
        livePockets()!.worn.map((i) => i.name),
        contains('flour-dusted apron'),
      );
      expect(livePockets()!.carrying.map((i) => i.name), contains('shop keys'));
    },
  );

  test('empty authored overlay does not wipe the card seed', () async {
    final cardOutfit = Pockets.cardJsonFrom(
      worn: const ['flour-dusted apron (well-worn)'],
      carrying: const ['shop keys'],
    );
    await db.insertCharacter(
      CharactersCompanion.insert(
        id: 'char-empty',
        name: 'Nemu',
        imagePath: const Value('/tmp/Nemu_e.png'),
        firstMessage: const Value('Hello, friend.'),
        alternateGreetings: const Value('["Get out."]'),
      ),
    );
    final card = CharacterCard(
      name: 'Nemu',
      imagePath: '/tmp/Nemu_e.png',
      firstMessage: 'Hello, friend.',
      alternateGreetings: const ['Get out.'],
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        characterEmotion: 'warm',
        emotionIntensity: 'mild',
        shortTermBond: 20,
        trustLevel: 10,
        timeOfDay: 'morning',
        needsSimEnabled: true,
        needsBaselineHunger: 80,
        inventory: cardOutfit,
        greetingSeeds: const [GreetingRealismSeed()],
      ),
    )..dbId = 'char-empty';
    await chat.setActiveCharacter(card);

    expect(chat.characterEmotion, 'warm');
    expect(chat.relationshipService.affectionScore, 20);
    expect(chat.relationshipService.trustLevel, 10);
    expect(chat.timeService.timeOfDay, 'morning');
    expect(chat.needsSimulation.vector['hunger'], 80);
    expect(
      livePockets()!.worn.map((i) => i.name),
      contains('flour-dusted apron'),
    );

    await chat.selectGreeting(1);

    expect(chat.greetingIndex, 1);
    expect(chat.messages.first.text, 'Get out.');
    expect(
      chat.characterEmotion,
      'warm',
      reason: 'empty {} overlay must inherit, not mute-wipe emotion',
    );
    expect(chat.relationshipService.affectionScore, 20);
    expect(chat.relationshipService.trustLevel, 10);
    expect(chat.timeService.timeOfDay, 'morning');
    expect(chat.needsSimulation.vector['hunger'], 80);
    expect(
      livePockets()!.worn.map((i) => i.name),
      contains('flour-dusted apron'),
      reason: 'empty overlay must not strip the card wardrobe',
    );
  });

  test(
    'group import/save with empty lists keeps blob angry alt+seed',
    () async {
      final angry = GreetingRealismSeed(
        characterEmotion: 'furious',
        emotionIntensity: 'strong',
        shortTermBond: -40,
      );
      final blobs = buildGroupRealismBlobs(
        seeds: {'mem-a': defaultGroupMemberRealismSeed()},
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
        alternateGreetings: const ['Get out.'],
        greetingSeeds: [angry],
      );
      final blob = blobs.defaultMemberJson;
      final repo = GroupChatRepository(storage, db);
      // Import-equivalent: parse alts/seeds out of the blob (empty lists
      // would wipe). Then save is a no-wipe round-trip.
      final group = GroupChat(
        id: 'grp-import-wipe',
        name: 'The House',
        firstMessage: 'Come in.',
        alternateGreetings: parseGroupAlternateGreetings(blob),
        greetingSeeds: parseGroupGreetingSeeds(blob),
        defaultMemberRealismState: blob,
        baselineRealismState: blobs.baselineJson,
      );
      await repo.save(group);
      await repo.reload();
      final loaded = repo.getById('grp-import-wipe')!;
      expect(loaded.alternateGreetings, ['Get out.']);
      expect(loaded.greetingSeeds.first!.characterEmotion, 'furious');
      expect(loaded.greetingSeeds.first!.emotionIntensity, 'strong');
    },
  );

  test(
    'repo.save writes patched alts/seeds back onto the in-memory GroupChat',
    () async {
      final angry = GreetingRealismSeed(characterEmotion: 'furious');
      final blobs = buildGroupRealismBlobs(
        seeds: {'mem-a': defaultGroupMemberRealismSeed()},
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      final repo = GroupChatRepository(storage, db);
      final group = GroupChat(
        id: 'grp-mem-patch',
        name: 'The House',
        firstMessage: 'Come in.',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await repo.save(group);
      group.alternateGreetings = ['Get out.'];
      group.greetingSeeds = [angry];
      await repo.save(group);
      expect(group.alternateGreetings, [
        'Get out.',
      ], reason: 'same object, no reload');
      expect(group.greetingSeeds.first!.characterEmotion, 'furious');
      expect(parseGroupAlternateGreetings(group.defaultMemberRealismState), [
        'Get out.',
      ]);
      expect(
        repo.getById('grp-mem-patch')!.greetingSeeds.first!.characterEmotion,
        'furious',
      );
    },
  );

  test(
    'unauthored group custom alt reaches RtR; authored furious and {} skip',
    () async {
      final angry = GreetingRealismSeed(
        characterEmotion: 'furious',
        emotionIntensity: 'strong',
      );
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-a': defaultGroupMemberRealismSeed(),
          'mem-b': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
        alternateGreetings: const [
          'Get out of my house.',
          'Same room.',
          'Who are you?',
        ],
        greetingSeeds: [angry, const GreetingRealismSeed(), null],
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-rtr',
          name: 'The House',
          firstMessage: const Value('Come in, friends.'),
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in [('mem-a', 'Ana'), ('mem-b', 'Bea')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.$1,
            groupId: 'grp-rtr',
            name: m.$2,
            firstMessage: const Value('Hi.'),
          ),
        );
      }
      final group = GroupChat(
        id: 'grp-rtr',
        name: 'The House',
        firstMessage: 'Come in, friends.',
        alternateGreetings: const [
          'Get out of my house.',
          'Same room.',
          'Who are you?',
        ],
        greetingSeeds: [angry, const GreetingRealismSeed(), null],
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.characterEmotion, 'furious');
      expect(
        testPostGreetingEvalEntered,
        isFalse,
        reason: 'authored furious overlay must skip RtR',
      );

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(2);
      expect(chat.greetingIndex, 2);
      expect(chat.messages.first.text, 'Same room.');
      expect(
        testPostGreetingEvalEntered,
        isFalse,
        reason: 'authored empty {} overlay must skip RtR',
      );

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(3);
      expect(chat.greetingIndex, 3);
      expect(chat.messages.first.text, 'Who are you?');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason:
            'unauthored group alt must reach eval, not skip for null _activeCharacter',
      );

      await chat.selectGreeting(0);
      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Come in, friends.');
      expect(chat.timeService.timeOfDay, 'morning');
    },
  );

  test(
    'GroupCardImporter construct+save+reload keeps alts and seeds on the blob',
    () async {
      final angry = GreetingRealismSeed(
        characterEmotion: 'furious',
        emotionIntensity: 'strong',
        shortTermBond: -40,
      );
      final blobs = buildGroupRealismBlobs(
        seeds: {'ana': defaultGroupMemberRealismSeed()},
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
        alternateGreetings: const ['Get out.'],
        greetingSeeds: [angry],
      );
      final card = GroupCard(
        name: 'Imported House',
        members: [CharacterCard(name: 'Ana', firstMessage: 'Hi.')],
        turnOrder: 'roundRobin',
        firstMessage: 'Come in.',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      final repo = GroupChatRepository(storage, db);
      final result = await GroupCardImporter(
        repo,
        storage,
        db,
      ).importCard(card);
      expect(
        result.created,
        isTrue,
        reason: 'importer must materialize the group',
      );
      expect(result.successCount, greaterThan(0));
      await repo.reload();
      final loaded = repo.groups.singleWhere((g) => g.name == 'Imported House');
      expect(loaded.alternateGreetings, ['Get out.']);
      expect(loaded.greetingSeeds, isNotEmpty);
      expect(loaded.greetingSeeds.first!.characterEmotion, 'furious');
      expect(loaded.greetingSeeds.first!.shortTermBond, -40);
      expect(parseGroupAlternateGreetings(loaded.defaultMemberRealismState), [
        'Get out.',
      ]);
      expect(
        parseGroupGreetingSeeds(
          loaded.defaultMemberRealismState,
        ).first!.characterEmotion,
        'furious',
      );
    },
  );

  test(
    'selectGreeting ignores a stale eval; swipe 0 still restores first_mes',
    () async {
      chat.testLlmServiceOverride = _DelayedStompLlm();
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-stale',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_stale.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      final card = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_stale.png',
        firstMessage: 'Hello, friend.',
        alternateGreetings: const ['Get out.'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'warm',
          emotionIntensity: 'mild',
          shortTermBond: 20,
          trustLevel: 10,
          timeOfDay: 'morning',
          needsSimEnabled: true,
          needsBaselineHunger: 80,
          greetingSeeds: const [null],
        ),
      )..dbId = 'char-stale';
      await chat.setActiveCharacter(card);

      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.greetingIndex, 0);

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason: 'unauthored alt 1 must start eval so a stale future exists',
      );

      await chat.selectGreeting(0);
      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);

      await Future<void>.delayed(const Duration(milliseconds: 280));

      expect(
        chat.characterEmotion,
        'warm',
        reason: 'stale eval must not apply ecstatic over swipe-0 first_mes',
      );
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
      expect(chat.messages.first.text, 'Hello, friend.');
    },
  );
}
