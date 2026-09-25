// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Kill-list pins for the clock contract. Each test must fail on
// d048e907 (before+0 skips the snap; after stamped pre-reconcile;
// nudge never writes after; host swipe clobbers a guest tick;
// capture drops start date; persistBefore hides metadata;
// unstamped Carmen fork snaps Day 1 09:00) and pass after the fix.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_kill_').path;
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
const _tenIso = '2026-09-25T10:00:00.000Z';
const _tenThirtyIso = '2026-09-25T10:30:00.000Z';
const _day1NineIso = '2026-06-28T09:00:00.000Z';
const _day3Iso = '2026-06-30T16:00:00.000Z';

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  String nextReply = '*Nia leans on the rail.*';
  bool cancelOnMinutes = false;
  Future<void> Function()? cancel;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield nextReply;
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
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedKillList';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  TimeService time() {
    return TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
      onPatchLastMessageRealismState: (_, _, _) {},
      getPorchLifePassageOfTime: () => true,
    )..seedFromV2OrExt(
      dayCount: 1,
      timeOfDay: 'morning',
      storyStartDate: '2026-09-25',
      storyStartTime: '10:30',
    );
  }

  test('K1: before without a chip falls through to the snap, not before+0', () {
    final t = time();
    final msg = ChatMessage(
      text: 'Hi.',
      sender: 'Nia',
      isUser: false,
      metadata: {
        'story_clock_before': _tenIso,
        'realism_state': {
          'storyClock': _tenThirtyIso,
          'storyStartDate': '2026-09-25',
        },
      },
    );
    backfillSlotClocks([msg], liveClock: t.clock, startDate: t.startDate);
    t.applySlotClock(resolved: slotClockAfter(msg.metadata));
    expect(
      t.clock,
      DateTime.utc(2026, 9, 25, 10, 30),
      reason: 'v1.4 slots have before and snap, never after/chip',
    );
  });

  test('K5: captured restore puts start date back with the clock', () {
    final t = time();
    t.restoreTimeFromRealismState({
      'storyClock': '2026-09-25T00:10:00.000Z',
      'storyStartDate': '2026-09-25',
    });
    expect(t.startDate, DateTime.utc(2026, 9, 25));
    t.captureLiveClock();
    t.rewindToBeforeIso('2026-09-24T23:40:00.000Z');
    expect(t.dayCount, 1);
    expect(t.startDate, DateTime.utc(2026, 9, 24));
    t.restoreCapturedClock();
    expect(t.clock, DateTime.utc(2026, 9, 25, 0, 10));
    expect(
      t.startDate,
      DateTime.utc(2026, 9, 25),
      reason: 'cancel across Day-1 midnight must not keep the pulled start',
    );
  });

  test('K6: persistStoryClockBefore never creates a bare slot map', () {
    final msg = ChatMessage(
      text: 'A',
      sender: 'Nia',
      isUser: false,
      swipes: ['A'],
      swipeIndex: 0,
      metadata: {
        'realism_state': {'shortTermBond': 40},
        'bond_delta': 5,
        'story_clock_before': _livedIso,
      },
      swipeMetadata: [null],
    );
    persistStoryClockBefore(msg, _livedIso);
    expect(msg.swipeMetadata[0], isNull);
    expect(
      msg.activeMetadata?['realism_state'],
      isNotNull,
      reason: 'null slot must keep falling back to message metadata',
    );
    expect(msg.activeMetadata?['bond_delta'], 5);
  });

  group('ChatService kill list', () {
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
        imagePath: '/tmp/nia-kill-clock.png',
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
        final swipes =
            (r['swipes'] as List<dynamic>?)?.cast<String>() ??
            [r['text'] as String];
        final swipeMeta = r['swipeMeta'] as List<dynamic>?;
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'k$i',
            sessionId: sid,
            position: i,
            sender: r['sender'] as String,
            isUser: r['user'] as bool,
            characterId: Value(r['cid'] as String?),
            swipes: Value(jsonEncode(swipes)),
            swipeIndex: Value(r['idx'] as int? ?? 0),
            metadata: Value(meta == null ? null : jsonEncode(meta)),
            swipeMetadata: Value(
              swipeMeta == null ? null : jsonEncode(swipeMeta),
            ),
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

    tearDown(() async {
      chat?.dispose();
      await db?.close();
    });

    test('K1 fixture: swipe HostOn pos 6 lands on 10:30 not 10:00', () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final dir = Directory.systemTemp.createTempSync('fpai_k1_swipe_');
      final work = File('${dir.path}/library.db');
      File('test/fixtures/v14_upgrade/library.db').copySync(work.path);
      db = AppDatabase.forReunification(work);
      await db!.ensureSchemaIsRepaired();
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
            ..setCharacterRepository(repo!);
      await storage!.initialized;
      await repo!.loadCharacters();
      final card = repo!.characters.firstWhere((c) => c.name == 'HostOn');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314131886');
      expect(chat!.timeService.clock, DateTime.utc(2026, 9, 25, 10, 30));
      await chat!.selectSwipe(6, 1);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 9, 25, 10, 30),
        reason: 'v1.4 swipe has before 10:00 and snap 10:30, no after/chip',
      );
      dir.deleteSync(recursive: true);
    });

    test('K1 fixture: fork Clocked pos 4 keeps the 3-day skip', () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final dir = Directory.systemTemp.createTempSync('fpai_k1_fork_');
      final work = File('${dir.path}/library.db');
      File('test/fixtures/v14_upgrade/library.db').copySync(work.path);
      db = AppDatabase.forReunification(work);
      await db!.ensureSchemaIsRepaired();
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
            ..setCharacterRepository(repo!);
      await storage!.initialized;
      await repo!.loadCharacters();
      final card = repo!.characters.firstWhere((c) => c.name == 'Clocked');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314133694');
      await chat!.forkFromMessage(4);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 9, 28, 18, 0),
        reason: 'v1.4 fork must take snap 18:00 Day 4, not before 09:30',
      );
      dir.deleteSync(recursive: true);
    });

    test('K2: named-clock reply stamps after from the final clock', () async {
      await boot();
      await chat!.setStoryClock(DateTime.utc(2026, 6, 29, 16, 37));
      llm.nextReply = 'It is 7:15 p.m. on the porch.';
      llm.nextMinutes = 30;
      await chat!.sendMessage('What time is it?');
      await drain();
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 19, 15));
      expect(
        last.activeMetadata?['story_clock_after'],
        '2026-06-29T19:15:00.000Z',
        reason: 'after must wait for named-clock reconcile, not the +30 tick',
      );
    });

    test(
      'K2: abort during regen post-gen restores the captured clock',
      () async {
        await boot();
        llm.nextMinutes = 30;
        await chat!.sendMessage('Hey.');
        await drain();
        final last = chat!.messages.lastWhere((m) => !m.isUser);
        final beforeIso = last.activeMetadata?['story_clock_before'] as String;
        llm.cancelOnMinutes = true;
        await chat!.regenerateLastMessage();
        await drain();
        expect(
          chat!.timeService.clock,
          DateTime.parse(beforeIso),
          reason: 'abort sets the clock to B\'s before, not A\'s after',
        );
        expect(last.activeMetadata?['story_clock_after'], beforeIso);
        expect(last.activeMetadata?['time_passed'], isNull);
        expect(
          chat!.guestActivityStatus,
          contains('Reply kept. Scene time and needs weren\'t updated.'),
        );
      },
    );

    test(
      'K3: nudge writes after; swipe away and back keeps the nudge',
      () async {
        await boot();
        llm.nextMinutes = 30;
        await chat!.sendMessage('Hey.');
        await drain();
        llm.nextMinutes = 5;
        await chat!.regenerateLastMessage();
        await drain();
        final idx = chat!.messages.lastIndexWhere((m) => !m.isUser);
        await chat!.nudgeTimePeriod(1);
        final nudged = chat!.timeService.clock;
        expect(
          chat!.messages[idx].activeMetadata?['story_clock_after'],
          chat!.timeService.storyClockIso,
        );
        await chat!.selectSwipe(idx, 0);
        await chat!.selectSwipe(idx, 1);
        expect(chat!.timeService.clock, nudged);
      },
    );

    test(
      'K3: nudge then regen twice keeps the nudge as the new before',
      () async {
        await boot();
        llm.nextMinutes = 30;
        await chat!.sendMessage('Hey.');
        await drain();
        await chat!.nudgeTimePeriod(1);
        final nudged = chat!.timeService.clock;
        llm.nextMinutes = 30;
        await chat!.regenerateLastMessage();
        await drain();
        await chat!.regenerateLastMessage();
        await drain();
        expect(
          chat!.timeService.clock,
          nudged.add(const Duration(minutes: 30)),
          reason: 'second regen must not rewind to the pre-nudge before',
        );
      },
    );

    test('K3: calendar-set tip then fork keeps the set clock', () async {
      await boot();
      llm.nextMinutes = 30;
      await chat!.sendMessage('Hey.');
      await drain();
      final setTo = DateTime.utc(2026, 7, 4, 12, 0);
      await chat!.setStoryClock(setTo);
      await chat!.forkFromMessage(chat!.messages.length - 1);
      await drain();
      expect(chat!.timeService.clock, setTo);
    });

    test(
      'K3: setStartDate shifts stamps so swipe stays in the new frame',
      () async {
        await boot();
        llm.nextMinutes = 30;
        await chat!.sendMessage('Hey.');
        await drain();
        llm.nextMinutes = 5;
        await chat!.regenerateLastMessage();
        await drain();
        final idx = chat!.messages.lastIndexWhere((m) => !m.isUser);
        final beforeShift = DateTime.parse(
          chat!.messages[idx].activeMetadata!['story_clock_after'] as String,
        );
        final oldStart = chat!.timeService.startDate;
        await chat!.setStoryStartDate(oldStart.add(const Duration(days: 10)));
        final afterShift = DateTime.parse(
          chat!.messages[idx].activeMetadata!['story_clock_after'] as String,
        );
        expect(afterShift.difference(beforeShift).inDays, 10);
        await chat!.selectSwipe(idx, 0);
        await chat!.selectSwipe(idx, 1);
        expect(chat!.timeService.clock, afterShift);
      },
    );

    test('K4: host swipe round-trip keeps a guest tick below', () async {
      await boot();
      const hAfter = '2026-06-29T10:30:00.000Z';
      const gAfter = '2026-06-29T10:40:00.000Z';
      Map<String, dynamic> hostSlot(String after) => {
        'story_clock_before': '2026-06-29T10:00:00.000Z',
        'story_clock_after': after,
        'realism_state': {'storyClock': after, 'storyStartDate': _startIso},
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Hi.',
            'swipes': ['Hi A', 'Hi B'],
            'idx': 0,
            'meta': hostSlot(hAfter),
            'swipeMeta': [hostSlot(hAfter), hostSlot(hAfter)],
          },
          {
            'sender': 'Gita',
            'user': false,
            'cid': 'guest-gita',
            'text': 'Ten minutes later.',
            'meta': {'story_clock_before': hAfter, 'story_clock_after': gAfter},
          },
        ],
        clock: gAfter,
        start: _startIso,
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 10, 40));
      await chat!.selectSwipe(0, 1);
      await chat!.selectSwipe(0, 0);
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 29, 10, 40),
        reason: 'host swipe must not apply 10:30 over a guest 10:40',
      );
    });

    test('K7: Carmen-class tip fork keeps the lived-in clock', () async {
      await boot();
      const snap = {
        'timeOfDay': 'morning',
        'dayCount': 1,
        'storyClock': _day1NineIso,
        'storyStartDate': _startIso,
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Morning.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Still here.',
            'meta': {'realism_state': snap},
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
      await chat!.forkFromMessage(2);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'unstamped tip must keep live, never Day 1 09:00',
      );
    });

    test('K7: Carmen-class mid-history fork never snaps Day 1 09:00', () async {
      await boot();
      const snap = {
        'timeOfDay': 'morning',
        'dayCount': 1,
        'storyClock': _day1NineIso,
        'storyStartDate': _startIso,
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Morning.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Later.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': 'And.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Tip.',
            'meta': {'realism_state': snap},
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      await chat!.forkFromMessage(2);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'lived-in Carmen mid-history fork keeps the live clock',
      );
    });
  });
}
