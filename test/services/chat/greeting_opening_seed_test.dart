// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Selecting an angry alt must apply that alt's authored opening, and
// swiping back to first_mes must restore the card seed. Proven red: before
// _applyGreetingOpeningSeed, selectGreeting only swapped text and either
// kept the friend seed or overwrote it with reading-the-room, never restored.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Captures delay + payload at stream start so a later swipe can change
/// the next eval without rewriting an already-started one.
class _PhasedGreetingLlm extends LLMService {
  Duration delay = Duration.zero;
  String payload = '{"emotion":"curious","emotion_intensity":"mild"}';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final wait = delay;
    final body = payload;
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    yield body;
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'PhasedGreetingLlm';
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


/// Settle fire-and-forget Drift requests inside this test's zone.
Future<void> _drainPendingDrift() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Same isolate: CI at 7cb122bf failed twice with Drift
    // "Channel was closed before receiving a response" — a background
    // isolate killed in the previous tearDown while persona load / porch
    // import was still in flight. No isolate channel, nothing to race.
    db = AppDatabase.forTesting(sameIsolate: true);
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
    await _drainPendingDrift();
    await db.close();
    await _drainPendingDrift();
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
    // Pin: loadSession fires unawaited porch import. File setUp uses
    // sameIsolate + tearDown drains/closes so this cannot flake as
    // Drift "Channel was closed" (CI job 99190537433, twice).
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

  test(
    'second unauthored alt then swipe 0: delayed eval-1 must not paint fury on first_mes',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-two-eval',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_two.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out.","Who are you?"]'),
        ),
      );
      final card = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_two.png',
        firstMessage: 'Hello, friend.',
        alternateGreetings: const ['Get out.', 'Who are you?'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'warm',
          emotionIntensity: 'mild',
          shortTermBond: 20,
          trustLevel: 10,
          timeOfDay: 'morning',
          needsSimEnabled: true,
          needsBaselineHunger: 80,
          greetingSeeds: const [null, null],
        ),
      )..dbId = 'char-two-eval';
      await chat.setActiveCharacter(card);

      expect(chat.characterEmotion, 'warm');
      expect(chat.greetingIndex, 0);

      llm.delay = const Duration(milliseconds: 180);
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(testPostGreetingEvalEntered, isTrue);

      llm.delay = Duration.zero;
      llm.payload = '{"emotion":"curious","emotion_intensity":"mild"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(2);
      expect(chat.greetingIndex, 2);
      expect(chat.messages.first.text, 'Who are you?');
      expect(testPostGreetingEvalEntered, isTrue);

      await chat.selectGreeting(0);
      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);

      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(
        chat.characterEmotion,
        'warm',
        reason:
            'delayed eval-1 must not paint fury onto swipe-0 first_mes after eval-2 finally-nulls the global token',
      );
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
      expect(chat.messages.first.text, 'Hello, friend.');
    },
  );

  test(
    'group custom unauthored alt persists RtR through first-speaker reload',
    () async {
      chat.testLlmServiceOverride = _PhasedGreetingLlm()
        ..payload = '{"emotion":"curious","emotion_intensity":"mild"}';
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
          id: 'grp-rtr-persist',
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
            groupId: 'grp-rtr-persist',
            name: m.$2,
            firstMessage: const Value('Hi.'),
          ),
        );
      }
      final group = GroupChat(
        id: 'grp-rtr-persist',
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
      expect(testPostGreetingEvalEntered, isFalse);

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(2);
      expect(testPostGreetingEvalEntered, isFalse);

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(3);
      expect(chat.greetingIndex, 3);
      expect(chat.messages.first.text, 'Who are you?');
      expect(testPostGreetingEvalEntered, isTrue);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (chat.isProcessingGreeting && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(chat.isProcessingGreeting, isFalse);

      expect(
        chat.characterEmotion,
        'curious',
        reason: 'unauthored group alt must keep the RtR result on live scalars',
      );
      final firstId = chat.characterIdFor(chat.groupCharacters.first);
      expect(
        chat.debugGroupSlotEmotion(firstId),
        'curious',
        reason: 'eval must be written back into the member slot, not inherit',
      );

      chat.debugReloadFirstGroupSpeakerScalars();
      expect(
        chat.characterEmotion,
        'curious',
        reason:
            'first-speaker reload must not throw RtR away for inherit baseline',
      );
    },
  );

  test(
    'reopen after persisted unauthored RtR keeps curious, not inherit',
    () async {
      chat.testLlmServiceOverride = _PhasedGreetingLlm()
        ..payload = '{"emotion":"curious","emotion_intensity":"mild"}';
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-a': defaultGroupMemberRealismSeed(),
          'mem-b': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
        alternateGreetings: const ['Who are you?'],
        greetingSeeds: [null],
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-rtr-reopen',
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
            groupId: 'grp-rtr-reopen',
            name: m.$2,
            firstMessage: const Value('Hi.'),
          ),
        );
      }
      final group = GroupChat(
        id: 'grp-rtr-reopen',
        name: 'The House',
        firstMessage: 'Come in, friends.',
        alternateGreetings: const ['Who are you?'],
        greetingSeeds: const [null],
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      final repo = GroupChatRepository(storage, db);
      await chat.setActiveGroup(group, groupRepo: repo);

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.messages.first.text, 'Who are you?');
      expect(testPostGreetingEvalEntered, isTrue);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (chat.isProcessingGreeting && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(chat.characterEmotion, 'curious');
      final sessionId = chat.currentSessionId!;

      await chat.setActiveGroup(group, groupRepo: repo);
      await chat.loadSession(sessionId);
      expect(chat.messages.first.text, 'Who are you?');
      expect(
        chat.characterEmotion,
        'curious',
        reason: 'reopen must keep persisted unauthored RtR, not inherit',
      );
      final firstId = chat.characterIdFor(chat.groupCharacters.first);
      expect(
        chat.debugGroupSlotEmotion(firstId),
        'curious',
        reason: 'member slots must still hold curious after reopen',
      );
    },
  );

  test(
    'empty first_mes pairs Stay./Get out. with warm/furious, no leftover warm',
    () async {
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-empty-first',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_empty.png'),
          firstMessage: const Value(''),
          alternateGreetings: const Value('["Stay.","Get out."]'),
        ),
      );
      final card = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_empty.png',
        firstMessage: '',
        alternateGreetings: const ['Stay.', 'Get out.'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'lonely',
          emotionIntensity: 'mild',
          shortTermBond: 5,
          trustLevel: 5,
          timeOfDay: 'morning',
          needsSimEnabled: true,
          needsBaselineHunger: 80,
          greetingSeeds: [
            GreetingRealismSeed(
              characterEmotion: 'warm',
              emotionIntensity: 'mild',
              shortTermBond: 20,
            ),
            GreetingRealismSeed(
              characterEmotion: 'furious',
              emotionIntensity: 'strong',
              shortTermBond: -40,
            ),
          ],
        ),
      )..dbId = 'char-empty-first';
      await chat.setActiveCharacter(card);

      expect(chat.openingAllGreetings, ['Stay.', 'Get out.']);
      expect(chat.messages, isNotEmpty);
      expect(chat.messages.first.text, 'Stay.');
      expect(
        chat.characterEmotion,
        'warm',
        reason:
            'empty first_mes: displayed 0 is alt[0] and overlay is seeds[0]',
      );
      expect(chat.relationshipService.affectionScore, 20);

      await chat.selectGreeting(1);

      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        chat.characterEmotion,
        'furious',
        reason: 'Get out. must read seeds[1], not leftover warm from seeds[0]',
      );
      expect(chat.characterEmotion, isNot('warm'));
      expect(chat.relationshipService.affectionScore, -40);
    },
  );

  test(
    "whitespace first_mes '   ' pairs Stay./warm and Get out./furious",
    () async {
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-ws-first',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_ws.png'),
          firstMessage: const Value('   '),
          alternateGreetings: const Value('["Stay.","Get out."]'),
        ),
      );
      final card = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_ws.png',
        firstMessage: '   ',
        alternateGreetings: const ['Stay.', 'Get out.'],
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'lonely',
          emotionIntensity: 'mild',
          shortTermBond: 5,
          trustLevel: 5,
          timeOfDay: 'morning',
          needsSimEnabled: true,
          needsBaselineHunger: 80,
          greetingSeeds: [
            GreetingRealismSeed(
              characterEmotion: 'warm',
              emotionIntensity: 'mild',
              shortTermBond: 20,
            ),
            GreetingRealismSeed(
              characterEmotion: 'furious',
              emotionIntensity: 'strong',
              shortTermBond: -40,
            ),
          ],
        ),
      )..dbId = 'char-ws-first';
      await chat.setActiveCharacter(card);

      expect(chat.openingAllGreetings, ['Stay.', 'Get out.']);
      expect(chat.messages, isNotEmpty);
      expect(chat.messages.first.text, 'Stay.');
      expect(
        chat.characterEmotion,
        'warm',
        reason:
            "first_mes '   ': displayed 0 is alt[0] and overlay is seeds[0]",
      );
      expect(chat.relationshipService.affectionScore, 20);

      await chat.selectGreeting(1);

      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        chat.characterEmotion,
        'furious',
        reason: 'Get out. must read seeds[1], not leftover warm from seeds[0]',
      );
      expect(chat.characterEmotion, isNot('warm'));
      expect(chat.relationshipService.affectionScore, -40);
    },
  );

  test(
    'member-greet unauthored RtR write-back persists eval into the whole cast',
    () async {
      chat.testLlmServiceOverride = _PhasedGreetingLlm()
        ..payload = '{"emotion":"curious","emotion_intensity":"mild"}';
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-a': defaultGroupMemberRealismSeed(),
          'mem-b': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-member-rtr',
          name: 'The House',
          firstMessage: const Value(''),
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-a',
          groupId: 'grp-member-rtr',
          name: 'Ana',
          firstMessage: const Value('Hi.'),
          alternateGreetings: const Value('["Who are you?"]'),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-b',
          groupId: 'grp-member-rtr',
          name: 'Bea',
          firstMessage: const Value('Hey.'),
        ),
      );
      final group = GroupChat(
        id: 'grp-member-rtr',
        name: 'The House',
        firstMessage: '',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.messages, isNotEmpty);
      expect(chat.messages.first.text, 'Hi.');
      expect(chat.openingAllGreetings, ['Hi.', 'Who are you?']);

      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Who are you?');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason: 'unauthored member-greet alt must reach RtR',
      );

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (chat.isProcessingGreeting && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(chat.isProcessingGreeting, isFalse);

      expect(
        chat.characterEmotion,
        'curious',
        reason: 'unauthored member-greet alt must keep the RtR result live',
      );
      for (final c in chat.groupCharacters) {
        final id = chat.characterIdFor(c);
        expect(
          chat.debugGroupSlotEmotion(id),
          'curious',
          reason:
              'member-greet RtR must persist into every current member slot, not only evalChar ($id)',
        );
      }

      chat.debugReloadFirstGroupSpeakerScalars();
      expect(
        chat.characterEmotion,
        'curious',
        reason:
            'first-speaker reload must not throw member-greet RtR away for inherit baseline',
      );
    },
  );

  test(
    'startNewChat after delayed unauthored alt: fury must not paint first_mes',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-newchat-stale',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_newchat.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      final card = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_newchat.png',
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
      )..dbId = 'char-newchat-stale';
      await chat.setActiveCharacter(card);

      expect(chat.characterEmotion, 'warm');
      expect(chat.messages.first.text, 'Hello, friend.');

      llm.delay = const Duration(milliseconds: 180);
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason: 'unauthored alt must start eval so a stale future exists',
      );

      await chat.startNewChat();
      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);

      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(
        chat.characterEmotion,
        'warm',
        reason:
            'delayed eval-1 must not paint fury onto New Chat first_mes',
      );
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
    },
  );

  test(
    'setActiveCharacter after delayed unauthored alt: fury must not paint next first_mes',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-switch-a',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_switch.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-switch-b',
          name: 'Mira',
          imagePath: const Value('/tmp/Mira_switch.png'),
          firstMessage: const Value('Hello, friend.'),
        ),
      );
      final nemu = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_switch.png',
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
      )..dbId = 'char-switch-a';
      await chat.setActiveCharacter(nemu);

      llm.delay = const Duration(milliseconds: 180);
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.messages.first.text, 'Get out.');
      expect(testPostGreetingEvalEntered, isTrue);

      final mira = CharacterCard(
        name: 'Mira',
        imagePath: '/tmp/Mira_switch.png',
        firstMessage: 'Hello, friend.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'warm',
          emotionIntensity: 'mild',
          shortTermBond: 20,
          trustLevel: 10,
          timeOfDay: 'morning',
          needsSimEnabled: true,
          needsBaselineHunger: 80,
        ),
      )..dbId = 'char-switch-b';
      await chat.setActiveCharacter(mira);

      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);

      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(
        chat.characterEmotion,
        'warm',
        reason:
            'delayed Nemu eval must not paint fury onto Mira first_mes',
      );
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.activeCharacter?.name, 'Mira');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
    },
  );

  test(
    'loadSession after delayed unauthored alt: fury must not paint loaded first_mes',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-load-stale',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_load.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      final nemu = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_load.png',
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
      )..dbId = 'char-load-stale';
      await chat.setActiveCharacter(nemu);

      expect(chat.characterEmotion, 'warm');
      expect(chat.messages.first.text, 'Hello, friend.');
      final openingSessionId = chat.currentSessionId!;

      await chat.startNewChat();
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.currentSessionId, isNot(openingSessionId));

      llm.delay = const Duration(milliseconds: 180);
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason: 'unauthored alt must start eval so a stale future exists',
      );

      await chat.loadSession(openingSessionId);
      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);

      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(
        chat.characterEmotion,
        'warm',
        reason:
            'delayed eval-1 must not paint fury onto loadSession first_mes',
      );
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
    },
  );

  test(
    'group blank first_mes + member empty first_mes opens Stay. with warm overlay',
    () async {
      final warm = GreetingRealismSeed(
        characterEmotion: 'warm',
        emotionIntensity: 'mild',
        shortTermBond: 20,
      );
      final furious = GreetingRealismSeed(
        characterEmotion: 'furious',
        emotionIntensity: 'strong',
        shortTermBond: -40,
      );
      final ext = FrontPorchExtensions(
        realismEnabled: true,
        characterEmotion: 'lonely',
        emotionIntensity: 'mild',
        shortTermBond: 5,
        trustLevel: 5,
        timeOfDay: 'morning',
        needsSimEnabled: true,
        needsBaselineHunger: 80,
        greetingSeeds: [warm, furious],
      );
      final blobs = buildGroupRealismBlobs(
        seeds: {'mem-nemu': defaultGroupMemberRealismSeed()},
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-blank-member',
          name: 'The House',
          firstMessage: const Value(''),
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-nemu',
          groupId: 'grp-blank-member',
          name: 'Nemu',
          firstMessage: const Value(''),
          alternateGreetings: const Value('["Stay.","Get out."]'),
          frontPorchExtensions: Value(jsonEncode(ext.toJson())),
        ),
      );
      final group = GroupChat(
        id: 'grp-blank-member',
        name: 'The House',
        firstMessage: '',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.messages, isNotEmpty, reason: 'member allGreetings must open');
      expect(chat.messages.first.text, 'Stay.');
      expect(chat.openingAllGreetings, ['Stay.', 'Get out.']);
      expect(
        chat.characterEmotion,
        'warm',
        reason: 'empty first_mes: displayed 0 is alt[0] and overlay is seeds[0]',
      );
      expect(chat.relationshipService.affectionScore, 20);

      await chat.startNewChat();
      expect(
        chat.messages,
        isNotEmpty,
        reason: 'New Chat in the group must also use member allGreetings',
      );
      expect(chat.messages.first.text, 'Stay.');
      expect(
        chat.characterEmotion,
        'warm',
        reason: 'New Chat must re-apply Stay./warm, not open empty',
      );
    },
  );

  test(
    'importChatPackage after delayed unauthored alt: fury must not paint imported first_mes',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-import-stale',
          name: 'Nemu',
          imagePath: const Value('/tmp/Nemu_import.png'),
          firstMessage: const Value('Hello, friend.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      final nemu = CharacterCard(
        name: 'Nemu',
        imagePath: '/tmp/Nemu_import.png',
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
      )..dbId = 'char-import-stale';
      await chat.setActiveCharacter(nemu);

      expect(chat.characterEmotion, 'warm');
      expect(chat.messages.first.text, 'Hello, friend.');

      llm.delay = const Duration(milliseconds: 180);
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason: 'unauthored alt must start eval so a stale future exists',
      );

      final outcome = await chat.importChatPackage(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'messages': [
                {'name': 'Nemu', 'is_user': false, 'mes': 'Hello, friend.'},
              ],
            }),
          ),
        ),
      );
      expect(outcome.fullRestore, isFalse);
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.characterEmotion, 'warm');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);

      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(
        chat.characterEmotion,
        'warm',
        reason:
            'delayed eval-1 must not paint fury onto importChatPackage first_mes',
      );
      expect(chat.messages.first.text, 'Hello, friend.');
      expect(chat.relationshipService.affectionScore, 20);
      expect(chat.relationshipService.trustLevel, 10);
      expect(chat.timeService.timeOfDay, 'morning');
      expect(chat.needsSimulation.vector['hunger'], 80);
    },
  );

  test(
    'group New Chat after completed unauthored fury reseeds inherit, not leftover fury',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-a': defaultGroupMemberRealismSeed(),
          'mem-b': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
        alternateGreetings: const ['Get out.'],
        greetingSeeds: const [null],
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-newchat-fury',
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
            groupId: 'grp-newchat-fury',
            name: m.$2,
            firstMessage: const Value('Hi.'),
          ),
        );
      }
      final group = GroupChat(
        id: 'grp-newchat-fury',
        name: 'The House',
        firstMessage: 'Come in, friends.',
        alternateGreetings: const ['Get out.'],
        greetingSeeds: const [null],
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.messages.first.text, 'Come in, friends.');

      llm.delay = Duration.zero;
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.greetingIndex, 1);
      expect(chat.messages.first.text, 'Get out.');
      expect(
        testPostGreetingEvalEntered,
        isTrue,
        reason: 'unauthored group alt must start RtR',
      );

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (chat.isProcessingGreeting && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(chat.isProcessingGreeting, isFalse);
      expect(
        chat.characterEmotion,
        'furious',
        reason: 'completed unauthored RtR must land fury before New Chat',
      );

      await chat.startNewChat();
      expect(chat.greetingIndex, 0);
      expect(chat.messages.first.text, 'Come in, friends.');
      expect(
        chat.characterEmotion,
        isNot('furious'),
        reason:
            'New Chat custom opener must apply overlay 0 / inherit, not leftover fury',
      );
      expect(
        ['', 'neutral'].contains(chat.characterEmotion),
        isTrue,
        reason: 'inherit/baseline (card inherit or member-seed), not leftover fury',
      );
      for (final c in chat.groupCharacters) {
        final id = chat.characterIdFor(c);
        expect(
          chat.debugGroupSlotEmotion(id),
          isNot('furious'),
          reason: 'New Chat must reseed member slots, not leave fury ($id)',
        );
      }
    },
  );

  test(
    'member-greet New Chat after completed fury reseeds inherit, not leftover fury',
    () async {
      final llm = _PhasedGreetingLlm();
      chat.testLlmServiceOverride = llm;
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-a': defaultGroupMemberRealismSeed(),
          'mem-b': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-member-newchat-fury',
          name: 'The House',
          firstMessage: const Value(''),
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-a',
          groupId: 'grp-member-newchat-fury',
          name: 'Ana',
          firstMessage: const Value('Hi.'),
          alternateGreetings: const Value('["Get out."]'),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-b',
          groupId: 'grp-member-newchat-fury',
          name: 'Bea',
          firstMessage: const Value('Hey.'),
        ),
      );
      final group = GroupChat(
        id: 'grp-member-newchat-fury',
        name: 'The House',
        firstMessage: '',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.messages.first.text, 'Hi.');
      expect(chat.openingAllGreetings, ['Hi.', 'Get out.']);

      llm.delay = Duration.zero;
      llm.payload = '{"emotion":"furious","emotion_intensity":"strong"}';
      testPostGreetingEvalEntered = false;
      await chat.selectGreeting(1);
      expect(chat.messages.first.text, 'Get out.');
      expect(testPostGreetingEvalEntered, isTrue);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (chat.isProcessingGreeting && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(chat.isProcessingGreeting, isFalse);
      expect(chat.characterEmotion, 'furious');

      await chat.startNewChat();
      expect(chat.messages.first.text, 'Hi.');
      expect(chat.greetingIndex, 0);
      expect(
        chat.characterEmotion,
        isNot('furious'),
        reason:
            'New Chat member-greet must apply overlay 0 / inherit, not leftover fury',
      );
      expect(
        ['', 'neutral'].contains(chat.characterEmotion),
        isTrue,
        reason: 'inherit/baseline (card inherit or member-seed), not leftover fury',
      );
    },
  );
}
