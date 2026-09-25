// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group fork walk-back (Opus 0ca90227 / 462ad7ec): stamped member restores;
// stamp-less reseeds from group card; chat-scoped clock is nearest stamp
// overall (NOT last roster member); wardrobes re-seed when Pockets is on.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, StoryClock;
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_gfork_').path;
        }
        return null;
      });
}

String _memberExt({
  required List<String> worn,
  required List<String> carrying,
}) {
  return jsonEncode({
    'realism_engine': {
      'realism_enabled': true,
      'inventory': Pockets.cardJsonFrom(worn: worn, carrying: carrying),
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

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

  Future<void> seedGroupSession({
    required String tipBlob,
    required List<
      ({
        String id,
        int pos,
        String sender,
        bool isUser,
        String text,
        Map<String, dynamic>? realism,
      })
    >
    messages,
    required GroupRealismBlobs blobs,
  }) async {
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-fork',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-ana',
        groupId: 'grp-fork',
        name: 'Ana',
        avatarFilename: const Value('Ana.png'),
        frontPorchExtensions: Value(
          _memberExt(worn: const ['red scarf'], carrying: const ['house key']),
        ),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: 'grp-fork',
        name: 'Bea',
        avatarFilename: const Value('Bea.png'),
        frontPorchExtensions: Value(
          _memberExt(worn: const ['blue coat'], carrying: const ['notebook']),
        ),
      ),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-gfork',
        characterId: const Value('group_grp-fork'),
        groupId: const Value('grp-fork'),
        realismEnabled: const Value(true),
        dayCount: const Value(99),
        timeOfDay: const Value('night'),
        groupRealismState: Value(tipBlob),
      ),
    );
    for (final m in messages) {
      final meta = m.realism == null
          ? null
          : jsonEncode({'realism_state': m.realism});
      await db.insertMessage(
        MessagesCompanion.insert(
          id: m.id,
          sessionId: 'sess-gfork',
          position: m.pos,
          sender: m.sender,
          isUser: m.isUser,
          swipes: Value(jsonEncode([m.text])),
          metadata: Value(meta),
          swipeMetadata: Value(
            meta == null ? null : jsonEncode([jsonDecode(meta)]),
          ),
        ),
      );
    }
  }

  test(
    'group fork: stamp/seed/wardrobe + clock is nearest stamp not last roster',
    () async {
      // THE CLOCK REGRESSION: roster order Ana then Bea. Bea stamped earlier
      // (day 40); Ana stamped later but closer to the fork (day 9). Old code
      // restored per-member in roster order → last stamped roster member
      // (Bea day 40) won. Correct: nearest stamp from the fork point (Ana
      // day 9). Pre-fix this assertion failed on day 40.
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'Ana': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 35,
            'trust': 20,
          },
          'Bea': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 42,
            'trust': 25,
          },
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );

      final tipBlob = jsonEncode({
        'perChar': {
          'Ana': {'affection': 200, 'trust': 90, 'dayCount': 99},
          'Bea': {'affection': 180, 'trust': 80, 'dayCount': 99},
        },
      });

      await seedGroupSession(
        tipBlob: tipBlob,
        blobs: blobs,
        messages: [
          (
            id: 'm0',
            pos: 0,
            sender: 'You',
            isUser: true,
            text: 'hi',
            realism: null,
          ),
          (
            id: 'm1',
            pos: 1,
            sender: 'Bea',
            isUser: false,
            text: 'early bea',
            realism: {
              'affectionScore': 70,
              'trustLevel': 40,
              'longTermScore': 0,
              'dayCount': 40,
              'timeOfDay': 'evening',
            },
          ),
          (
            id: 'm2',
            pos: 2,
            sender: 'You',
            isUser: true,
            text: 'and you',
            realism: null,
          ),
          (
            id: 'm3',
            pos: 3,
            sender: 'Ana',
            isUser: false,
            text: 'late ana',
            realism: {
              'affectionScore': 90,
              'trustLevel': 50,
              'longTermScore': 0,
              'dayCount': 9,
              'timeOfDay': 'afternoon',
            },
          ),
          (
            id: 'm4',
            pos: 4,
            sender: 'You',
            isUser: true,
            text: 'fork me',
            realism: null,
          ),
        ],
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-fork',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.messages, hasLength(5));
      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
      expect(chat.groupCharacters.map((c) => c.name).toList(), ['Ana', 'Bea']);

      expect(chat.getAffectionForGroupCharacter(ana), 200);
      expect(chat.getAffectionForGroupCharacter(bea), 180);
      expect(
        chat.timeService.dayCount,
        9,
        reason: 'one-path load applies tip.after (Ana day 9), not session 99',
      );

      await chat.forkFromMessage(4);

      expect(
        chat.getAffectionForGroupCharacter(ana),
        90,
        reason: 'Ana restores nearest stamp in the kept prefix',
      );
      expect(
        chat.getAffectionForGroupCharacter(bea),
        70,
        reason: 'Bea restores her earlier stamp (not tip 180)',
      );
      expect(
        chat.timeService.dayCount,
        9,
        reason:
            'nearest stamp from fork is Ana day 9 — NOT last-roster '
            'Bea day 40 (the pre-fix bug) and NOT tip 99',
      );
      expect(chat.timeService.timeOfDay, 'afternoon');

      final anaPockets = chat.pocketsFor(chat.characterIdFor(ana));
      final beaPockets = chat.pocketsFor(chat.characterIdFor(bea));
      expect(beaPockets, isNotNull);
      expect(beaPockets!.worn.map((i) => i.name), contains('blue coat'));
      expect(anaPockets, isNotNull);
      expect(anaPockets!.worn.map((i) => i.name), contains('red scarf'));

      expect(chat.parentSessionId, 'sess-gfork');
      expect(chat.forkIndex, 4);
    },
  );

  test(
    'group stamp-less fork at Day-99 tip reseeds bond and keeps Day 99',
    () async {
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'Ana': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 35,
            'trust': 20,
          },
          'Bea': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 42,
            'trust': 25,
          },
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );

      final tipBlob = jsonEncode({
        'perChar': {
          'Ana': {'affection': 200, 'trust': 90},
          'Bea': {'affection': 180, 'trust': 80},
        },
      });

      await seedGroupSession(
        tipBlob: tipBlob,
        blobs: blobs,
        messages: [
          (
            id: 'm0',
            pos: 0,
            sender: 'You',
            isUser: true,
            text: 'hi',
            realism: null,
          ),
          (
            id: 'm1',
            pos: 1,
            sender: 'Ana',
            isUser: false,
            text: 'hello',
            // stamp-less entire transcript
            realism: null,
          ),
          (
            id: 'm2',
            pos: 2,
            sender: 'You',
            isUser: true,
            text: 'fork',
            realism: null,
          ),
        ],
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-fork',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
      // Transcript: [0 You first user, 1 Ana, 2 You tip]. Fork index 2
      // is the tip, after the first user turn — Day 99, not the start.
      expect(
        chat.timeService.dayCount,
        99,
        reason: 'stamp-less Day-99 session stays Day 99 on load (not floored)',
      );
      expect(chat.getAffectionForGroupCharacter(ana), 200);
      final tipClock = chat.timeService.clock;
      final tipStart = chat.timeService.startDate;

      await chat.forkFromMessage(2);

      expect(chat.getAffectionForGroupCharacter(ana), 35);
      expect(chat.getAffectionForGroupCharacter(bea), 42);
      expect(
        chat.timeService.dayCount,
        99,
        reason: 'fork at tip of a Day-99 chat lands on Day 99, not Day 1',
      );
      expect(chat.timeService.clock, tipClock);
      expect(chat.timeService.startDate, tipStart);
      expect(chat.timeService.timeOfDay, 'night');
      expect(
        chat.pocketsFor(chat.characterIdFor(bea))?.worn.map((i) => i.name),
        contains('blue coat'),
      );
    },
  );

  test(
    'group stamp-less + Pockets OFF keeps live wardrobe (HIDES≠erase)',
    () async {
      // Fix #1 of d285304d: keptPockets must run. With Pockets on, seed always
      // re-applies the card kit and this guard is unreachable.
      await storage.realismSettings.setPocketsEnabled(true);

      final blobs = buildGroupRealismBlobs(
        seeds: {
          'Ana': {...defaultGroupMemberRealismSeed(), 'affection': 35},
          'Bea': {...defaultGroupMemberRealismSeed(), 'affection': 42},
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      // Tip pockets with an acquired item the card does not list.
      final tipBlob = jsonEncode({
        'perChar': {
          'Ana': {
            'affection': 200,
            'pockets': Pockets.cardJsonFrom(
              worn: const ['acquired cloak'],
              carrying: const ['found coin'],
            ),
          },
          'Bea': {
            'affection': 180,
            'pockets': Pockets.cardJsonFrom(
              worn: const ['acquired hat'],
              carrying: const [],
            ),
          },
        },
      });

      await seedGroupSession(
        tipBlob: tipBlob,
        blobs: blobs,
        messages: [
          (
            id: 'm0',
            pos: 0,
            sender: 'You',
            isUser: true,
            text: 'hi',
            realism: null,
          ),
          (
            id: 'm1',
            pos: 1,
            sender: 'Ana',
            isUser: false,
            text: 'hello',
            realism: null,
          ),
        ],
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-fork',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      final anaId = chat.characterIdFor(ana);
      // Confirm tip wardrobe loaded, then hide the feature.
      expect(
        chat.pocketsFor(anaId)?.worn.map((i) => i.name),
        contains('acquired cloak'),
      );
      await storage.realismSettings.setPocketsEnabled(false);
      // pocketsFor hides when off — read via group realism state instead.
      expect(
        chat.getRealismStateForGroupCharacter(ana)?['pockets'],
        isNotNull,
        reason: 'live slot still holds wardrobe while feature is off',
      );

      await chat.forkFromMessage(1);

      expect(chat.getAffectionForGroupCharacter(ana), 35);
      final after = chat.getRealismStateForGroupCharacter(ana);
      final pockets = after?['pockets'];
      expect(
        pockets,
        isNotNull,
        reason: 'HIDES≠erase: stamp-less reseed kept kit',
      );
      expect(
        (pockets as Map)['worn']?.toString() ?? '',
        contains('acquired cloak'),
        reason: 'must keep tip wardrobe, not wipe or re-seed card apron',
      );
    },
  );

  test('group stamp-less empty-blob fork at Day-99 tip stays Day 99', () async {
    // Fix #2 of d285304d: parseGroupTimeSeed returns null when blobs are {}.
    final emptyBlobs = const GroupRealismBlobs(
      defaultMemberJson: '{}',
      baselineJson: '{}',
    );
    // Still need perChar affection seeds for bond reseed — put them without
    // top-level time so parseGroupTimeSeed is null.
    final seedsOnly = jsonEncode({
      'perChar': {
        'Ana': {...defaultGroupMemberRealismSeed(), 'affection': 35}
          ..remove('timeOfDay')
          ..remove('dayCount'),
        'Bea': {...defaultGroupMemberRealismSeed(), 'affection': 42}
          ..remove('timeOfDay')
          ..remove('dayCount'),
      },
    });

    final tipBlob = jsonEncode({
      'perChar': {
        'Ana': {'affection': 200},
        'Bea': {'affection': 180},
      },
    });

    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-fork',
        name: 'The Porch',
        defaultMemberRealismState: Value(seedsOnly),
        baselineRealismState: const Value('{}'),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-ana',
        groupId: 'grp-fork',
        name: 'Ana',
        avatarFilename: const Value('Ana.png'),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: 'grp-fork',
        name: 'Bea',
        avatarFilename: const Value('Bea.png'),
      ),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-gfork',
        characterId: const Value('group_grp-fork'),
        groupId: const Value('grp-fork'),
        realismEnabled: const Value(true),
        dayCount: const Value(99),
        timeOfDay: const Value('night'),
        groupRealismState: Value(tipBlob),
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm0',
        sessionId: 'sess-gfork',
        position: 0,
        sender: 'You',
        isUser: true,
        swipes: Value(jsonEncode(['hi'])),
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm1',
        sessionId: 'sess-gfork',
        position: 1,
        sender: 'Ana',
        isUser: false,
        swipes: Value(jsonEncode(['yo'])),
      ),
    );

    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-fork',
        name: 'The Porch',
        defaultMemberRealismState: seedsOnly,
        baselineRealismState: emptyBlobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );

    // Transcript: [0 You first user, 1 Ana tip]. Fork index 1 is the
    // tip, after the first user turn — Day 99 of this chat.
    expect(
      chat.timeService.dayCount,
      99,
      reason: 'empty-blob Day-99 session stays Day 99 on load (not floored)',
    );
    final tipClock = chat.timeService.clock;
    final anchorBefore = chat.timeService.storyStartDateIso;
    await chat.forkFromMessage(1);
    expect(
      chat.timeService.dayCount,
      99,
      reason: 'fork at tip of a Day-99 chat lands on Day 99, not Day 1',
    );
    expect(chat.timeService.clock, tipClock);
    expect(chat.timeService.timeOfDay, 'night');
    expect(
      chat.timeService.storyStartDateIso,
      anchorBefore,
      reason: 'tip-fork keeps the Day-99 start — never re-anchor on today',
    );
  });

  test(
    'group stamp-less fork at greeting (before first user) lands on Day 1',
    () async {
      // Counterpart to the two tip-forks: greeting is the story start.
      // Fork index 0 is before the first user turn → Day 1 of the start.
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'Ana': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 35,
            'trust': 20,
          },
          'Bea': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 42,
            'trust': 25,
          },
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      final tipBlob = jsonEncode({
        'perChar': {
          'Ana': {'affection': 200, 'trust': 90, 'dayCount': 99},
          'Bea': {'affection': 180, 'trust': 80, 'dayCount': 99},
        },
      });

      await seedGroupSession(
        tipBlob: tipBlob,
        blobs: blobs,
        messages: [
          (
            id: 'm0',
            pos: 0,
            sender: 'Ana',
            isUser: false,
            text: 'Greeting.',
            realism: null,
          ),
          (
            id: 'm1',
            pos: 1,
            sender: 'You',
            isUser: true,
            text: 'hi',
            realism: null,
          ),
          (
            id: 'm2',
            pos: 2,
            sender: 'Ana',
            isUser: false,
            text: 'Later.',
            realism: null,
          ),
        ],
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-fork',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(chat.messages, hasLength(3));
      expect(chat.messages[0].isUser, isFalse);
      expect(chat.messages[1].isUser, isTrue);
      expect(
        chat.timeService.dayCount,
        99,
        reason: 'live tip is still Day 99 before the start-fork',
      );
      final start = chat.timeService.startDate;

      await chat.forkFromMessage(0);

      expect(chat.forkIndex, 0);
      expect(
        chat.timeService.dayCount,
        1,
        reason:
            'fork at/before the first user turn lands on Day 1 of the start, '
            'not the Day-99 tip',
      );
      expect(chat.timeService.startDate, start);
      expect(
        StoryClock.dateOnly(chat.timeService.clock),
        StoryClock.dateOnly(start),
        reason: 'Day 1 clock sits on the story start date',
      );
    },
  );

  test(
    'group stamp-less fork prefers live re-anchor over blob storyStartDate',
    () async {
      // Mirrors 1:1 user-re-anchor test — group floor used to prefer
      // timeSeed.storyStartDate and would snap back to 1887.
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'Ana': {...defaultGroupMemberRealismSeed(), 'affection': 35},
          'Bea': {...defaultGroupMemberRealismSeed(), 'affection': 42},
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
        storyStartDate: '1887-06-01',
      );
      final tipBlob = jsonEncode({
        'perChar': {
          'Ana': {'affection': 200},
          'Bea': {'affection': 180},
        },
      });

      await seedGroupSession(
        tipBlob: tipBlob,
        blobs: blobs,
        messages: [
          (
            id: 'm0',
            pos: 0,
            sender: 'You',
            isUser: true,
            text: 'hi',
            realism: null,
          ),
          (
            id: 'm1',
            pos: 1,
            sender: 'Ana',
            isUser: false,
            text: 'hello',
            realism: null,
          ),
        ],
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-fork',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );

      chat.timeService.seedFromV2OrExt(
        dayCount: 4,
        timeOfDay: 'morning',
        storyStartDate: '1890-03-01',
      );
      expect(chat.timeService.storyStartDateIso, '1890-03-01');

      await chat.forkFromMessage(1);

      expect(
        chat.timeService.storyStartDateIso,
        '1890-03-01',
        reason: 'group floor must keep live re-anchor, not blob 1887',
      );
      expect(
        chat.getAffectionForGroupCharacter(
          chat.groupCharacters.firstWhere((c) => c.name == 'Ana'),
        ),
        35,
      );
    },
  );

  test(
    'group story_day (standalone clock) rewinds day and keeps anchor',
    () async {
      // Engine-off path: no realism_state, only top-level story_day.
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'Ana': {...defaultGroupMemberRealismSeed(), 'affection': 35},
          'Bea': {...defaultGroupMemberRealismSeed(), 'affection': 42},
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      final tipBlob = jsonEncode({
        'perChar': {
          'Ana': {'affection': 200},
          'Bea': {'affection': 180},
        },
      });

      await seedGroupSession(
        tipBlob: tipBlob,
        blobs: blobs,
        messages: [
          (
            id: 'm0',
            pos: 0,
            sender: 'You',
            isUser: true,
            text: 'hi',
            realism: null,
          ),
          (
            id: 'm1',
            pos: 1,
            sender: 'Ana',
            isUser: false,
            text: 'day five',
            realism: null,
          ),
        ],
      );
      // Patch message m1 with story_day only (standalone clock stamp).
      await db.updateMessage(
        MessagesCompanion(
          id: const Value('m1'),
          metadata: Value(jsonEncode({'story_day': 5})),
          swipeMetadata: Value(
            jsonEncode([
              {'story_day': 5},
            ]),
          ),
        ),
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-fork',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );

      // Force a non-today story start so re-anchor would be visible.
      chat.timeService.seedFromV2OrExt(
        dayCount: 30,
        timeOfDay: 'night',
        storyStartDate: '2026-06-01',
      );
      final anchorBefore = chat.timeService.storyStartDateIso;
      expect(chat.timeService.dayCount, 30);

      await chat.forkFromMessage(1);
      expect(chat.timeService.dayCount, 5);
      expect(
        chat.timeService.storyStartDateIso,
        anchorBefore,
        reason: 'story_day restore must not today-anchor',
      );
    },
  );
}
