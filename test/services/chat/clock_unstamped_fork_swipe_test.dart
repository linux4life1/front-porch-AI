// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// B2 ChatService: a lived-in chat backfilled from UNSTAMPED rows. Forking
// at, or swiping to, an older reply lands on THAT reply's story_clock_after,
// never the live tip clock.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show slotClockAfter;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_unstamp_fork_').path;
        }
        return null;
      });
}

const _startIso = '2026-06-28';
const _livedIso = '2026-07-01T00:10:00.000Z';

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentUnstamp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;

  Future<void> drain() async {
    for (
      var i = 0;
      i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> boot11() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!)
          ..testLlmServiceOverride = _SilentLlm();
    await storage!.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-unstamp-fork.png',
      frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
    );
    await repo!.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
  }

  Future<void> plantUnstamped11() async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    Future<void> row({
      required String id,
      required int pos,
      required String sender,
      required bool user,
      required String text,
      Map<String, dynamic>? meta,
      List<String>? swipes,
      List<Map<String, dynamic>?>? swipeMeta,
      int idx = 0,
    }) {
      return db!.insertMessage(
        MessagesCompanion.insert(
          id: id,
          sessionId: sid,
          position: pos,
          sender: sender,
          isUser: user,
          swipes: Value(jsonEncode(swipes ?? [text])),
          swipeIndex: Value(idx),
          metadata: Value(meta == null ? null : jsonEncode(meta)),
          swipeMetadata: Value(
            swipeMeta == null ? null : jsonEncode(swipeMeta),
          ),
        ),
      );
    }

    await row(
      id: 'u0',
      pos: 0,
      sender: 'Nia',
      user: false,
      text: 'one',
      meta: {'story_day': 1},
    );
    await row(id: 'u1', pos: 1, sender: 'You', user: true, text: 'hi');
    await row(
      id: 'u2',
      pos: 2,
      sender: 'Nia',
      user: false,
      text: 'two',
      meta: {'story_day': 2},
    );
    await row(id: 'u3', pos: 3, sender: 'You', user: true, text: 'again');
    await row(
      id: 'u4',
      pos: 4,
      sender: 'Nia',
      user: false,
      text: 'three',
      meta: {'story_day': 3},
      swipes: ['three-old', 'three'],
      swipeMeta: [
        {'story_day': 2},
        {'story_day': 3},
      ],
      idx: 1,
    );
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        storyClock: const Value(_livedIso),
        storyStartDate: const Value(_startIso),
        timeOfDay: const Value('night'),
        dayCount: const Value(4),
      ),
    );
    await chat!.reloadCurrentSession();
    await drain();
  }

  ChatMessage botAt(int i) => chat!.messages[i];

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    '1:1 fork at an older unstamped reply uses that reply after, not the tip',
    () async {
      await boot11();
      await plantUnstamped11();
      final mid = botAt(2);
      final tip = botAt(4);
      final midAfter = slotClockAfter(mid.activeMetadata);
      final tipAfter = slotClockAfter(tip.activeMetadata);
      expect(midAfter, isNotNull);
      expect(tipAfter, isNotNull);
      expect(
        midAfter,
        isNot(tipAfter),
        reason: 'backfill must give the older reply its own after',
      );

      await chat!.forkFromMessage(2);
      await drain();
      expect(
        chat!.timeService.clock,
        midAfter,
        reason: 'fork lands on the fork-point slot after, never the live tip',
      );
    },
  );

  test(
    '1:1 swipe to an older unstamped swipe uses that swipe after, not the tip',
    () async {
      await boot11();
      await plantUnstamped11();
      final tip = botAt(4);
      expect(tip.swipeIndex, 1);
      final tipAfter = slotClockAfter(tip.activeMetadata);
      final olderSlot = tip.swipeMetadata[0];
      final olderAfter = slotClockAfter(olderSlot);
      expect(olderAfter, isNotNull);
      expect(
        olderAfter,
        isNot(tipAfter),
        reason: 'the buried swipe must keep its own after',
      );

      await chat!.swipeMessage(4, -1);
      await drain();
      expect(botAt(4).swipeIndex, 0);
      expect(
        chat!.timeService.clock,
        olderAfter,
        reason: 'swipe applies that swipe\'s after, never the rejected tip',
      );
    },
  );

  test(
    'group fork at an older unstamped reply uses that reply after',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'passage_of_time_default': true,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      chat =
          ChatService(
              KoboldService(storage!),
              UserPersonaService(db!),
              storage!,
              WorldRepository(storage!, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(CharacterRepository(db!, storage!))
            ..testLlmServiceOverride = _SilentLlm();
      await storage!.initialized;
      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-ana': defaultGroupMemberRealismSeed(),
          'mem-bea': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: false,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db!.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-unstamp',
          name: 'Unstamp',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in [
        (id: 'mem-ana', name: 'Ana'),
        (id: 'mem-bea', name: 'Bea'),
      ]) {
        await db!.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.id,
            groupId: 'grp-unstamp',
            name: m.name,
            firstMessage: const Value('Evening.'),
          ),
        );
      }
      await db!.insertSession(
        SessionsCompanion.insert(
          id: 'sess-unstamp',
          characterId: const Value('group_grp-unstamp'),
          groupId: const Value('grp-unstamp'),
          storyClock: const Value(_livedIso),
          storyStartDate: const Value(_startIso),
          dayCount: const Value(4),
        ),
      );
      Future<void> row({
        required String id,
        required int pos,
        required String sender,
        required bool user,
        required String text,
        Map<String, dynamic>? meta,
      }) {
        return db!.insertMessage(
          MessagesCompanion.insert(
            id: id,
            sessionId: 'sess-unstamp',
            position: pos,
            sender: sender,
            isUser: user,
            swipes: Value(jsonEncode([text])),
            metadata: Value(meta == null ? null : jsonEncode(meta)),
          ),
        );
      }

      await row(
        id: 'g0',
        pos: 0,
        sender: 'Ana',
        user: false,
        text: 'one',
        meta: {'story_day': 1},
      );
      await row(id: 'g1', pos: 1, sender: 'You', user: true, text: 'hi');
      await row(
        id: 'g2',
        pos: 2,
        sender: 'Bea',
        user: false,
        text: 'two',
        meta: {'story_day': 2},
      );
      await row(id: 'g3', pos: 3, sender: 'You', user: true, text: 'again');
      await row(
        id: 'g4',
        pos: 4,
        sender: 'Ana',
        user: false,
        text: 'three',
        meta: {'story_day': 3},
      );

      await chat!.setActiveGroup(
        GroupChat(
          id: 'grp-unstamp',
          name: 'Unstamp',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage!, db!),
      );
      for (var i = 0; i < 40 && chat!.groupCharacters.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await drain();
      final midAfter = slotClockAfter(botAt(2).activeMetadata);
      final tipAfter = slotClockAfter(botAt(4).activeMetadata);
      expect(midAfter, isNotNull);
      expect(midAfter, isNot(tipAfter));
      await chat!.forkFromMessage(2);
      await drain();
      expect(
        chat!.timeService.clock,
        midAfter,
        reason: 'group fork uses the fork-point after, not the tip',
      );
    },
  );
}
