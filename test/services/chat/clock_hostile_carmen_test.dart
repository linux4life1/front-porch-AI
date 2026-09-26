// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hostile HIGH pins. Real Carmen greetings have no realism_state;
// replies carry frozen Day-1 storyClock snaps. Existing Carmen tests
// plant a greeting snap, so they never saw this shape.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show StoryClock, backfillSlotClocks, slotClockAfter, slotClockBefore;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_hostile_carmen_')
              .path;
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
const _day1Nine = '2026-06-28T09:00:00.000Z';
const _day1NineThirty = '2026-06-28T09:30:00.000Z';
const _day3Iso = '2026-06-30T16:00:00.000Z';
const _day3Before = '2026-06-30T23:40:00.000Z';
const _day4Iso = '2026-07-01T00:10:00.000Z';

final _day3 = DateTime.utc(2026, 6, 30, 16, 0);
final _day4 = DateTime.utc(2026, 7, 1, 0, 10);
final _day3Floor = DateTime.utc(2026, 6, 30, 23, 40);
final _day1Start = DateTime.utc(2026, 6, 28, 9, 0);

const _frozenSnap = {
  'storyClock': _day1Nine,
  'storyStartDate': _startIso,
  'timeOfDay': 'morning',
  'dayCount': 1,
};

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Carmen stays on the porch.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HostileCarmen';
}

ChatMessage _bot(String text, Map<String, dynamic> meta) {
  return ChatMessage(
    text: text,
    sender: 'Carmen',
    isUser: false,
    metadata: Map<String, dynamic>.from(meta),
    swipeIndex: 0,
    swipes: [text],
  );
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

  Future<void> boot({bool passage = true}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': passage,
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
    await storage!.initialized;
    final carmen = CharacterCard(
      name: 'Carmen',
      firstMessage: 'Evening.',
      imagePath: '/tmp/carmen-hostile.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: passage,
        needsBaselineHunger: 80,
        needsBaselineBladder: 80,
        needsBaselineEnergy: 80,
        needsBaselineSocial: 80,
        needsBaselineFun: 80,
        needsBaselineHygiene: 80,
        needsBaselineComfort: 80,
      ),
    );
    await repo!.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _needs});
    await drain();
  }

  Future<void> plant({
    required List<Map<String, Object?>> rows,
    String? clock,
    String start = _startIso,
    int day = 3,
    String tod = 'afternoon',
    bool passage = true,
  }) async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final meta = r['meta'] as Map<String, dynamic>?;
      final swipes = r['swipes'] as List<String>? ?? [r['text'] as String];
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'hc$i',
          sessionId: sid,
          position: i,
          sender: r['sender'] as String,
          isUser: r['user'] as bool,
          swipes: Value(jsonEncode(swipes)),
          metadata: Value(meta == null ? null : jsonEncode(meta)),
        ),
      );
    }
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        passageOfTimeEnabled: Value(passage),
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

  List<Map<String, Object?>> v14Rows() => [
    {'sender': 'Carmen', 'user': false, 'text': 'Evening.'},
    {'sender': 'You', 'user': true, 'text': 'Hi.'},
    {
      'sender': 'Carmen',
      'user': false,
      'text': 'Still here.',
      'meta': {'realism_state': _frozenSnap},
    },
  ];

  ChatMessage tipBot() =>
      chat!.messages.lastWhere((m) => !m.isUser && m.sender != 'System');

  Future<void> expectNothingPersistedAs0900(String sid) async {
    final row = await db!.getSessionById(sid);
    expect(row?.storyClock, isNot(_day1Nine));
    final rows = await db!.getMessagesForSession(sid);
    for (final r in rows) {
      if (r.metadata != null && r.metadata!.isNotEmpty) {
        final decoded = jsonDecode(r.metadata!);
        if (decoded is Map) {
          expect(
            decoded['story_clock_after'],
            isNot(_day1Nine),
            reason: 'open must not persist a frozen 09:00 as the slot after',
          );
          if (decoded['story_clock_after'] != null) {
            expect(
              decoded['story_clock_before'],
              isNot(_day1Nine),
              reason: 'lived-in open must not persist 09:00 as the slot before',
            );
          }
        }
      }
    }
  }

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    chat = null;
    db = null;
  });

  test('HIGH-1 v1.4 open keeps Day 3 16:00 and persists no 09:00', () async {
    await boot();
    await plant(rows: v14Rows(), clock: _day3Iso, day: 3);
    expect(chat!.timeService.clock, _day3);
    expect(chat!.timeService.dayCount, 3);
    expect(slotClockAfter(tipBot().activeMetadata), _day3);
    await chat!.flushPendingSaves();
    await expectNothingPersistedAs0900(chat!.currentSessionId!);
  });

  test('HIGH-1 regen ticks once from Day 3 16:00; nothing is 09:xx', () async {
    await boot();
    await plant(rows: v14Rows(), clock: _day3Iso, day: 3);
    expect(chat!.timeService.clock, _day3);

    llm.nextMinutes = 0;
    await chat!.regenerateLastMessage();
    await drain();
    final tip = tipBot();
    final before = slotClockBefore(tip.activeMetadata);
    expect(before, _day3, reason: 'regen rewinds to the tip before');
    final elapsed = StoryClock.resolvedElapsedMinutes(
      minutes: llm.nextMinutes,
      newDay: false,
      continuousInstant: false,
    );
    final after = before!.add(Duration(minutes: elapsed));
    expect(
      slotClockAfter(tip.activeMetadata),
      after,
      reason: 'after is before + resolvedElapsedMinutes, not a hardcoded 2',
    );
    expect(chat!.timeService.clock, after);
    expect(chat!.timeService.clock.hour, isNot(9));
    expect(before, isNot(_day1Start));
    expect(after, isNot(_day1Start));
  });

  test('HIGH-1 fork-from-tip / delete keep Day 3 16:00', () async {
    await boot();
    await plant(rows: v14Rows(), clock: _day3Iso, day: 3);
    expect(chat!.timeService.clock, _day3);

    final sid = chat!.currentSessionId!;
    await chat!.forkFromMessage(2);
    await drain();
    expect(chat!.timeService.clock, _day3);
    expect(chat!.parentSessionId, sid);

    final tipIdx = chat!.messages.indexOf(tipBot());
    final beforeDelete = chat!.timeService.clock;
    chat!.deleteMessage(tipIdx);
    await drain();
    expect(chat!.timeService.clock, beforeDelete);
    expect(chat!.timeService.clock, isNot(_day1Start));
  });

  test(
    'v1.4 fork at pos 2 is Day 3 16:00 (tip-live; no stored after)',
    () async {
      await boot();
      await plant(rows: v14Rows(), clock: _day3Iso, day: 3);
      // Pos 2 has a frozen Day-1 snap and no stored after/chip. Ladder:
      // skip frozen snap, then tip-live = the session clock (Day 3 16:00).
      // Neighbour AFTER would be 09:30 only if a later pair donated it.
      await chat!.forkFromMessage(2);
      await drain();
      expect(chat!.timeService.clock, _day3);
      expect(chat!.timeService.clock, isNot(DateTime.utc(2026, 6, 28, 9, 30)));
    },
  );

  test('HIGH-1 first regen ticks the eval once, never twice', () async {
    await boot();
    await plant(rows: v14Rows(), clock: _day3Iso, day: 3);
    final opened = chat!.timeService.clock;
    expect(opened, _day3);
    llm.nextMinutes = 30;
    await chat!.regenerateLastMessage();
    await drain();
    // Regen rewinds to the tip before, then post-gen applies minutes
    // once. A double tick would be +60.
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 30));
    expect(chat!.timeService.clock, isNot(DateTime.utc(2026, 6, 30, 17, 0)));
    expect(chat!.timeService.clock, isNot(_day1Start));
  });

  test('HIGH-2 tip before-only takes max(live, own before)', () async {
    await boot();
    await plant(
      rows: [
        {'sender': 'Carmen', 'user': false, 'text': 'Evening.'},
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Late.',
          'meta': {'story_clock_before': _day3Before},
        },
      ],
      clock: _day4Iso,
      day: 4,
      tod: 'night',
    );
    expect(chat!.timeService.clock, _day4);
    expect(slotClockAfter(tipBot().activeMetadata), _day4);
  });

  test('HIGH-2 live earlier than own before floors at own before', () async {
    await boot();
    await plant(
      rows: [
        {'sender': 'Carmen', 'user': false, 'text': 'Evening.'},
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Late.',
          'meta': {'story_clock_before': _day3Before},
        },
      ],
      clock: _day3Iso,
      day: 3,
    );
    expect(chat!.timeService.clock, _day3Floor);
    expect(slotClockAfter(tipBot().activeMetadata), _day3Floor);
  });

  test('later neighbour donates BEFORE; earlier donates AFTER', () {
    final later = _bot('later.', {
      'story_clock_before': _day1Nine,
      'story_clock_after': _day1NineThirty,
    });
    final earlierEmpty = _bot('greeting.', {});
    backfillSlotClocks(
      [earlierEmpty, later],
      liveClock: _day3,
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(
      slotClockAfter(earlierEmpty.activeMetadata),
      _day1Start,
      reason: 'later neighbour contributes its BEFORE (09:00), not AFTER 09:30',
    );

    final earlier = _bot('earlier.', {
      'story_clock_before': _day1Nine,
      'story_clock_after': _day1NineThirty,
    });
    final history = _bot('history.', {});
    final tip = _bot('tip.', {});
    backfillSlotClocks(
      [earlier, history, tip],
      liveClock: _day3,
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(
      slotClockAfter(history.activeMetadata),
      DateTime.utc(2026, 6, 28, 9, 30),
      reason: 'earlier neighbour contributes its AFTER',
    );
  });

  test('v1.4 fork at pos 0 and pos 1 is Day 1 09:00, not 09:30', () async {
    await boot();
    await plant(rows: v14Rows(), clock: _day3Iso, day: 3);

    await chat!.forkFromMessage(0);
    await drain();
    expect(chat!.timeService.clock, _day1Start);
    expect(chat!.timeService.clock, isNot(DateTime.utc(2026, 6, 28, 9, 30)));

    await boot();
    await plant(rows: v14Rows(), clock: _day3Iso, day: 3);
    await chat!.forkFromMessage(1);
    await drain();
    expect(chat!.timeService.clock, _day1Start);
    expect(chat!.timeService.clock, isNot(DateTime.utc(2026, 6, 28, 9, 30)));
  });

  // Fork-at-greeting (not greeting-as-tip). The planted chat is
  // greeting-only so the greeting is the tip at open; forkFromMessage(0)
  // is the Day-1-of-start writer (message_clock :287/:345), which must
  // use the chat's stored startDate, never today.
  test('fork at greeting is Day 1 of the stored start, never today', () async {
    await boot();
    await plant(
      rows: [
        {'sender': 'Carmen', 'user': false, 'text': 'Evening.'},
      ],
      clock: _day3Iso,
      day: 3,
    );
    expect(
      chat!.timeService.clock,
      _day3,
      reason:
          'open live is the session stored clock (Day 3 16:00), '
          'not today and not Day 1',
    );
    expect(
      chat!.timeService.startDate,
      DateTime.utc(2026, 6, 28),
      reason: 'open startDate is the session stored start, not today',
    );
    expect(
      StoryClock.dateOnly(chat!.timeService.clock),
      isNot(StoryClock.todayAnchor()),
      reason: 'session scalars must load; live must not default to today',
    );

    await chat!.forkFromMessage(0);
    await drain();
    expect(
      chat!.timeService.clock,
      _day1Start,
      reason:
          'fork-at-greeting Day 1 is 2026-06-28 09:00 from the '
          'stored start, never today',
    );
    expect(
      chat!.timeService.clock,
      isNot(StoryClock.representativeTime(StoryClock.todayAnchor(), 'morning')),
      reason: '_day1OfStoryStart must not use todayAnchor',
    );
  });

  test('PoT OFF open/swipe/fork/delete do not move the live clock', () async {
    await boot(passage: false);
    await plant(
      rows: [
        {'sender': 'Carmen', 'user': false, 'text': 'Evening.'},
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Still here.',
          'meta': {'realism_state': _frozenSnap},
          'swipes': ['Still here.', 'Other swipe.'],
        },
      ],
      clock: _day3Iso,
      day: 3,
      passage: false,
    );
    final opened = chat!.timeService.clock;
    expect(opened, _day3, reason: 'open must not apply a frozen 09:00 snap');

    final tipIdx = chat!.messages.indexOf(tipBot());
    var before = chat!.timeService.clock;
    await chat!.swipeMessage(tipIdx, 1);
    await drain();
    expect(chat!.timeService.clock, before);

    before = chat!.timeService.clock;
    await chat!.forkFromMessage(tipIdx);
    await drain();
    expect(chat!.timeService.clock, before);

    before = chat!.timeService.clock;
    final del = chat!.messages.indexOf(tipBot());
    chat!.deleteMessage(del);
    await drain();
    expect(chat!.timeService.clock, before);
  });
}
