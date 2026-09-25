// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Earlier clock gaps: nudge then tail-delete, ChatService cancel/fail
// across Day-1 midnight, mid-chat non-tail delete (1:1 and group), and
// a real guest swipe that pins per-slot before/after.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_gaps_').path;
        }
        return null;
      });
}

const _needs = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

const _startIso = '2026-06-28';
const _livedIso = '2026-06-29T16:37:00.000Z';
const _day3Iso = '2026-06-30T16:00:00.000Z';
const _preCrossIso = '2026-06-28T23:40:00.000Z';

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  bool cancelOnMinutes = false;
  bool throwOnMinutes = false;
  Future<void> Function()? cancel;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia leans on the rail.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      if (cancelOnMinutes) {
        cancelOnMinutes = false;
        await cancel?.call();
        return;
      }
      if (throwOnMinutes) {
        throw Exception('gaps midnight eval throw');
      }
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedClockGaps';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  late _ScriptedLlm llm;

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

  Future<void> boot() async {
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
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!)
          ..testLlmServiceOverride = llm;
    llm.cancel = () => chat!.cancelRealismEval();
    await storage!.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-clk-gaps.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: true,
        needsBaselineHunger: 80,
        needsBaselineBladder: 80,
        needsBaselineEnergy: 80,
        needsBaselineSocial: 80,
        needsBaselineFun: 80,
        needsBaselineHygiene: 80,
        needsBaselineComfort: 80,
      ),
    );
    await repo!.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _needs});
    await drain();
  }

  Future<void> plant({
    required List<Map<String, Object?>> rows,
    required String clock,
    required String start,
    int day = 2,
    String tod = 'afternoon',
  }) async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final meta = r['meta'] as Map<String, dynamic>?;
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'g$i',
          sessionId: sid,
          position: i,
          sender: r['sender'] as String,
          isUser: r['user'] as bool,
          characterId: Value(r['cid'] as String?),
          swipes: Value(jsonEncode([r['text'] as String])),
          metadata: Value(meta == null ? null : jsonEncode(meta)),
        ),
      );
    }
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        passageOfTimeEnabled: const Value(true),
        passageOfTimeGateMigrated: const Value(true),
        storyClock: Value(clock),
        storyStartDate: Value(start),
        timeOfDay: Value(tod),
        dayCount: Value(day),
      ),
    );
    await chat!.reloadCurrentSession();
    await drain();
  }

  Future<void> enterGroup() async {
    const groupId = 'grp-gaps';
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-nia': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'afternoon',
      dayCount: 3,
    );
    await db!.insertGroup(
      GroupsCompanion.insert(
        id: groupId,
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [
      (id: 'mem-nia', name: 'Nia'),
      (id: 'mem-bea', name: 'Bea'),
    ]) {
      await db!.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.id,
          groupId: groupId,
          name: m.name,
          firstMessage: const Value('Evening.'),
          avatarFilename: Value('${m.id}.png'),
        ),
      );
    }
    await chat!.setActiveGroup(
      GroupChat(
        id: groupId,
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    await drain();
  }

  int lastBotIndex() => chat!.messages.lastIndexWhere((m) => !m.isUser);

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

  test('nudge then tail delete returns the clock to pre-nudge', () async {
    await boot();
    llm.nextMinutes = 30;
    await chat!.sendMessage('Hey.');
    await drain();
    final preNudge = chat!.timeService.clock;
    await chat!.nudgeTimePeriod(1);
    expect(chat!.timeService.clock, isNot(preNudge));
    chat!.deleteMessage(lastBotIndex());
    await drain();
    expect(
      chat!.timeService.clock,
      preNudge,
      reason: 'deleting the nudged tail bot must restore the pre-nudge clock',
    );
  });

  test('cancel across Day-1 midnight leaves clock and start date', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Greeting.',
          'meta': {
            'story_clock_before': _startIso,
            'story_clock_after': '2026-06-28T23:10:00.000Z',
          },
        },
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Late.',
          'meta': {
            'story_clock_before': '2026-06-28T23:10:00.000Z',
            'story_clock_after': _preCrossIso,
            'realism_state': {
              'storyClock': _preCrossIso,
              'storyStartDate': _startIso,
            },
          },
        },
      ],
      clock: _preCrossIso,
      start: _startIso,
      day: 1,
      tod: 'night',
    );
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 28, 23, 40));
    expect(chat!.timeService.dayCount, 1);
    final start = chat!.timeService.startDate;
    llm.nextMinutes = 30;
    llm.cancelOnMinutes = true;
    await chat!.regenerateLastMessage();
    await drain();
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 28, 23, 40),
      reason: 'cancelled regen must not cross into Day 2',
    );
    expect(chat!.timeService.dayCount, 1);
    expect(chat!.timeService.startDate, start);
  });

  test('error across Day-1 midnight leaves clock and start date', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Greeting.',
          'meta': {
            'story_clock_before': _startIso,
            'story_clock_after': '2026-06-28T23:10:00.000Z',
          },
        },
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Late.',
          'meta': {
            'story_clock_before': '2026-06-28T23:10:00.000Z',
            'story_clock_after': _preCrossIso,
            'realism_state': {
              'storyClock': _preCrossIso,
              'storyStartDate': _startIso,
            },
          },
        },
      ],
      clock: _preCrossIso,
      start: _startIso,
      day: 1,
      tod: 'night',
    );
    final start = chat!.timeService.startDate;
    llm.nextMinutes = 30;
    llm.throwOnMinutes = true;
    try {
      await chat!.regenerateLastMessage();
    } catch (_) {}
    await drain();
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 28, 23, 40),
      reason: 'failed regen must not cross into Day 2',
    );
    expect(chat!.timeService.dayCount, 1);
    expect(chat!.timeService.startDate, start);
  });

  test('1:1 mid-chat bot delete leaves the clock unchanged', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Greeting.',
          'meta': {
            'story_clock_before': '2026-06-28T09:00:00.000Z',
            'story_clock_after': '2026-06-28T09:00:00.000Z',
          },
        },
        {'sender': 'You', 'user': true, 'text': '1'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Mid.',
          'meta': {
            'story_clock_before': _livedIso,
            'story_clock_after': _livedIso,
          },
        },
        {'sender': 'You', 'user': true, 'text': '2'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Tip.',
          'meta': {
            'story_clock_before': _day3Iso,
            'story_clock_after': _day3Iso,
          },
        },
      ],
      clock: _day3Iso,
      start: _startIso,
      day: 3,
    );
    expect(chat!.messages[2].text, 'Mid.');
    expect(chat!.messages[2].isUser, isFalse);
    chat!.deleteMessage(2);
    await drain();
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 30, 16, 0),
      reason: 'deleting a real mid-chat bot, not the greeting, keeps the tip',
    );
  });

  test('group mid-chat bot delete leaves the clock unchanged', () async {
    await boot();
    await enterGroup();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'cid': 'mem-nia',
          'text': 'First.',
          'meta': {
            'story_clock_before': _livedIso,
            'story_clock_after': _livedIso,
          },
        },
        {
          'sender': 'Bea',
          'user': false,
          'cid': 'mem-bea',
          'text': 'Mid.',
          'meta': {
            'story_clock_before': _livedIso,
            'story_clock_after': _livedIso,
          },
        },
        {
          'sender': 'Nia',
          'user': false,
          'cid': 'mem-nia',
          'text': 'Tip.',
          'meta': {
            'story_clock_before': _day3Iso,
            'story_clock_after': _day3Iso,
          },
        },
      ],
      clock: _day3Iso,
      start: _startIso,
      day: 3,
    );
    expect(chat!.messages[1].text, 'Mid.');
    chat!.deleteMessage(1);
    await drain();
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 30, 16, 0),
      reason: 'group non-tail delete must not move the chat clock',
    );
  });

  test('guest swipe round trip pins per-slot before and after', () async {
    await boot();
    await chat!.setStoryClock(DateTime.utc(2026, 6, 29, 16, 37));
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: '/tmp/riley-gaps-swipe.png',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    await repo!.addCharacter(guest);
    await chat!.joinSceneGuest(guest);
    await drain();
    llm.nextMinutes = 30;
    await chat!.speakGuestNow(
      chat!.sceneGuestCards.firstWhere((c) => c.name == 'Riley'),
    );
    await drain();
    final idx = chat!.messages.lastIndexWhere((m) => m.sender == 'Riley');
    final msg = chat!.messages[idx];
    final beforeIso = msg.activeMetadata?['story_clock_before'] as String;
    final afterA = msg.activeMetadata?['story_clock_after'] as String;
    expect(beforeIso, isNotNull);
    expect(afterA, isNotNull);
    final clockA = DateTime.parse(afterA);
    expect(chat!.timeService.clock, clockA);

    llm.nextMinutes = 5;
    await chat!.regenerateLastMessage();
    await drain();
    final afterB = msg.swipeMetadata[1]?['story_clock_after'] as String;
    final beforeB = msg.swipeMetadata[1]?['story_clock_before'] as String;
    expect(beforeB, beforeIso);
    expect(msg.swipeMetadata[0]?['story_clock_before'], beforeIso);
    expect(msg.swipeMetadata[0]?['story_clock_after'], afterA);
    expect(afterB, isNot(afterA));
    expect(chat!.timeService.clock, DateTime.parse(afterB));

    await chat!.selectSwipe(idx, 0);
    expect(
      chat!.timeService.clock,
      DateTime.parse(afterA),
      reason: 'swipe back to A equals slot A story_clock_after',
    );
    await chat!.selectSwipe(idx, 1);
    expect(
      chat!.timeService.clock,
      DateTime.parse(afterB),
      reason: 'swipe to B equals slot B story_clock_after',
    );
    expect(
      DateTime.parse(afterA),
      DateTime.parse(beforeIso).add(const Duration(minutes: 30)),
    );
    expect(
      DateTime.parse(afterB),
      DateTime.parse(beforeIso).add(const Duration(minutes: 5)),
    );
    expect(StoryClock.parse(beforeIso), isNotNull);
  });
}
