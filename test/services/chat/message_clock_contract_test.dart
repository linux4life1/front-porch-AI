// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One clock contract: message-level before is shared by every swipe;
// each slot stores after; fail/cancel/abort put back the captured live
// clock; fork/import prefer after, then before+chip, then snap, then
// before. Rewind before Day 1 pulls the start date (same as reconcile).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_msg_clock_').path;
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

const _livedIso = '2026-06-29T16:37:00.000Z';
const _startIso = '2026-06-28';
const _day1NineIso = '2026-06-28T09:00:00.000Z';
const _day1NineThirtyIso = '2026-06-28T09:30:00.000Z';
const _day3Iso = '2026-06-30T16:00:00.000Z';
final _lived = DateTime.utc(2026, 6, 29, 16, 37);
final _day1NineThirty = DateTime.utc(2026, 6, 28, 9, 30);
final _day3 = DateTime.utc(2026, 6, 30, 16, 0);

const _day1NineSnap = {
  'timeOfDay': 'morning',
  'dayCount': 1,
  'storyClock': _day1NineIso,
  'storyStartDate': _startIso,
  'characterEmotion': 'neutral',
  'emotionIntensity': 'mild',
};

const _day3Snap = {
  'timeOfDay': 'afternoon',
  'dayCount': 3,
  'storyClock': _day3Iso,
  'storyStartDate': _startIso,
  'characterEmotion': 'neutral',
  'emotionIntensity': 'mild',
};

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  bool failNextChat = false;
  bool cancelNextEval = false;
  Future<void> Function()? cancel;
  bool _aborted = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      if (failNextChat) {
        failNextChat = false;
        throw Exception('regen failed');
      }
      if (_aborted) return;
      yield '*Nia leans on the rail.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      if (cancelNextEval) {
        cancelNextEval = false;
        _aborted = true;
        await cancel?.call();
        return;
      }
      if (_aborted) return;
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (_aborted) return;
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
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedMessageClock';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  late _ScriptedLlm llm;

  Future<void> drainTurn() async {
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

  Future<void> boot({bool porchLife = true}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': porchLife,
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
      imagePath: '/tmp/nia-msg-clock.png',
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
    await drainTurn();
  }

  Future<void> plantOldTranscript({String? timePassed}) async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    for (var i = 0; i < 40; i++) {
      final seeded = await db!.getSessionById(sid);
      if (seeded?.storyClock != null && seeded!.storyClock!.isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final greetingMeta = jsonEncode({'realism_state': _day1NineSnap});
    final lastMeta = jsonEncode({
      'realism_state': _day1NineSnap,
      'time_passed': ?timePassed,
    });

    await db!.deleteMessagesForSession(sid);
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'clk-old-g',
        sessionId: sid,
        position: 0,
        sender: 'Nia',
        isUser: false,
        swipes: Value(jsonEncode(['Evening.'])),
        metadata: Value(greetingMeta),
        swipeMetadata: Value(jsonEncode([jsonDecode(greetingMeta)])),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'clk-old-u',
        sessionId: sid,
        position: 1,
        sender: 'You',
        isUser: true,
        swipes: Value(jsonEncode(['Hey.'])),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'clk-old-b',
        sessionId: sid,
        position: 2,
        sender: 'Nia',
        isUser: false,
        swipes: Value(jsonEncode(['*Nia leans on the rail.*'])),
        metadata: Value(lastMeta),
        swipeMetadata: Value(jsonEncode([jsonDecode(lastMeta)])),
      ),
    );
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        passageOfTimeEnabled: const Value(true),
        passageOfTimeGateMigrated: const Value(true),
        storyClock: const Value(_livedIso),
        storyStartDate: const Value(_startIso),
        timeOfDay: const Value('afternoon'),
        dayCount: const Value(2),
      ),
    );
    await chat!.reloadCurrentSession();
    await drainTurn();
    expect(chat!.timeService.clock, _lived);
  }

  ChatMessage lastBot() => chat!.messages.lastWhere((m) => !m.isUser);

  int lastBotIndex() => chat!.messages.lastIndexWhere((m) => !m.isUser);

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

  TimeService _time({bool porch = true}) {
    return TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
      onPatchLastMessageRealismState: (_, _, _) {},
      getPorchLifePassageOfTime: () => porch,
    )..seedFromV2OrExt(
      dayCount: 2,
      timeOfDay: 'afternoon',
      storyStartDate: _startIso,
      storyStartTime: '16:37',
    );
  }

  group('chip minutes', () {
    test('chip text only — numeric fields and Next morning are unknown', () {
      expect(minutesFromTimePassed('5 min'), 5);
      expect(minutesFromTimePassed('1 hr'), 60);
      expect(minutesFromTimePassed('2 hr'), 120);
      expect(minutesFromTimePassed('same moment'), 0);
      expect(minutesFromTimePassed('Next morning'), isNull);
      expect(minutesFromTimePassed(5), isNull);
      expect(minutesFromTimePassed(null), isNull);
      expect(minutesRecordedForClockRewind({'time_passed': '5 min'}), 5);
      expect(minutesRecordedForClockRewind({'minutes': 12}), isNull);
      expect(minutesRecordedForClockRewind({'minutes_elapsed': 8}), isNull);
    });
  });

  group('TimeService contract', () {
    test('capture / restore puts the clock back after a rewind', () {
      final t = _time();
      t.captureLiveClock();
      t.rewindToBeforeIso(_day1NineIso);
      expect(t.clock, DateTime.utc(2026, 6, 28, 9, 0));
      t.restoreCapturedClock();
      expect(t.clock, _lived);
    });

    test('backfill fills after from pair, chip, snap, or live', () {
      final t = _time();
      ChatMessage slot(Map<String, dynamic> meta) => ChatMessage(
        text: 'Hi.',
        sender: 'Nia',
        isUser: false,
        metadata: Map<String, dynamic>.from(meta),
      );

      final stamped = slot({
        'story_clock_after': _day1NineThirtyIso,
        'story_clock_before': _day1NineIso,
        'time_passed': '5 min',
      });
      backfillSlotClocks([stamped], liveClock: t.clock);
      t.applySlotClock(resolved: slotClockAfter(stamped.metadata));
      expect(t.clock, _day1NineThirty);

      final fromChip = slot({
        'story_clock_before': _day1NineIso,
        'time_passed': '5 min',
      });
      backfillSlotClocks([fromChip], liveClock: t.clock);
      t.applySlotClock(resolved: slotClockAfter(fromChip.metadata));
      expect(t.clock, DateTime.utc(2026, 6, 28, 9, 5));

      final empty = slot({});
      backfillSlotClocks([empty], liveClock: DateTime.utc(2026, 6, 28, 9, 5));
      t.applySlotClock(resolved: slotClockAfter(empty.metadata));
      expect(t.clock, DateTime.utc(2026, 6, 28, 9, 5));
    });

    test('backfill prefers after, else before plus minutes, else snap', () {
      final t = _time();
      ChatMessage slot(Map<String, dynamic> meta) => ChatMessage(
        text: 'Hi.',
        sender: 'Nia',
        isUser: false,
        metadata: Map<String, dynamic>.from(meta),
      );

      final stamped = slot({
        'story_clock_after': _day1NineThirtyIso,
        'story_clock_before': _day1NineIso,
        'time_passed': '5 min',
        'realism_state': {'storyClock': _day3Iso},
      });
      backfillSlotClocks([stamped], liveClock: t.clock);
      t.applySlotClock(resolved: slotClockAfter(stamped.metadata));
      expect(t.clock, _day1NineThirty);

      final fromChip = slot({
        'story_clock_before': _day1NineIso,
        'time_passed': '30 min',
        'realism_state': {'storyClock': _day3Iso},
      });
      backfillSlotClocks([fromChip], liveClock: t.clock);
      t.applySlotClock(resolved: slotClockAfter(fromChip.metadata));
      expect(t.clock, _day1NineThirty);

      final greeting = slot({
        'realism_state': {
          'storyClock': _day1NineIso,
          'storyStartDate': _startIso,
        },
      });
      final fromSnap = slot({
        'realism_state': {'storyClock': _day3Iso, 'storyStartDate': _startIso},
      });
      backfillSlotClocks([greeting, fromSnap], liveClock: t.clock);
      t.applySlotClock(resolved: slotClockAfter(fromSnap.metadata));
      expect(t.clock, _day3);

      final beforeAndSnap = slot({
        'story_clock_before': _day1NineIso,
        'realism_state': {'storyClock': _day3Iso, 'storyStartDate': _startIso},
      });
      backfillSlotClocks([greeting, beforeAndSnap], liveClock: t.clock);
      t.applySlotClock(resolved: slotClockAfter(beforeAndSnap.metadata));
      expect(
        t.clock,
        _day3,
        reason: 'before without chip minutes uses the snap, not before+0',
      );
    });

    test('rewind before Day 1 pulls the start date, same as reconcile', () {
      final t = _time();
      t.applySlotClock(resolved: DateTime.utc(2026, 6, 28, 0, 10));
      t.loadTimeScalars(
        timeOfDay: 'night',
        dayCount: 1,
        startDayOfWeek: DateTime.utc(2026, 6, 28).weekday,
        storyClock: '2026-06-28T00:10:00.000Z',
        storyStartDate: _startIso,
      );
      t.rewindToBeforeIso('2026-06-27T23:40:00.000Z');
      expect(t.clock, DateTime.utc(2026, 6, 27, 23, 40));
      expect(t.dayCount, 1);
      expect(t.startDate, DateTime.utc(2026, 6, 27));
    });

    test('message before is shared across slots via putIfAbsent', () {
      final msg = ChatMessage(
        text: 'A',
        sender: 'Nia',
        isUser: false,
        swipes: ['A', 'B', 'C'],
        swipeIndex: 1,
        metadata: {
          'story_clock_before': _livedIso,
          'realism_state': {'shortTermBond': 12},
        },
        swipeMetadata: [
          {'time_passed': '2 hr'},
          {'time_passed': '30 min'},
          null,
        ],
      );
      expect(knownStoryClockBefore(msg), _livedIso);
      persistStoryClockBefore(msg, _livedIso);
      expect(msg.metadata?['story_clock_before'], _livedIso);
      expect(msg.swipeMetadata[0]?['story_clock_before'], _livedIso);
      expect(msg.swipeMetadata[1]?['story_clock_before'], _livedIso);
      expect(msg.swipeMetadata[2], isNull);
      msg.swipeIndex = 2;
      expect(msg.activeMetadata?['realism_state'], isNotNull);
      persistStoryClockBefore(msg, _day1NineIso);
      expect(msg.metadata?['story_clock_before'], _livedIso);
      expect(msg.swipeMetadata[0]?['story_clock_before'], _livedIso);
      expect(msg.swipeMetadata[2], isNull);
    });
  });

  test(
    'regen twice lands the same time and stamps before on the new slot',
    () async {
      await boot();
      await plantOldTranscript();
      await chat!.regenerateLastMessage();
      await drainTurn();
      final first = chat!.timeService.clock;
      expect(first, DateTime.utc(2026, 6, 29, 17, 7));
      expect(lastBot().activeMetadata?['story_clock_before'], _livedIso);

      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(chat!.timeService.clock, first);
      expect(lastBot().activeMetadata?['story_clock_before'], _livedIso);
    },
  );

  test(
    'regen three times on a lived-in chat stays on the same clock',
    () async {
      await boot();
      await plantOldTranscript();
      await chat!.regenerateLastMessage();
      await drainTurn();
      final first = chat!.timeService.clock;
      expect(first, DateTime.utc(2026, 6, 29, 17, 7));
      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(chat!.timeService.clock, first);
      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(chat!.timeService.clock, first);
      expect(lastBot().activeMetadata?['story_clock_before'], _livedIso);
      expect(lastBot().swipes.length, 4);
    },
  );

  test('old bot with no chip: regen, swipe back, regen has no creep', () async {
    await boot();
    await plantOldTranscript();
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 17, 7));
    final idx = lastBotIndex();
    await chat!.selectSwipe(idx, 0);
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 29, 17, 7),
      reason: 'shared before 16:37 + 30, never live+30 creep',
    );
  });

  test(
    'old bot with a 2 hr chip: regen, swipe back, regen has no backwards',
    () async {
      await boot();
      await plantOldTranscript(timePassed: '2 hr');
      await chat!.regenerateLastMessage();
      await drainTurn();
      final first = chat!.timeService.clock;
      expect(first, DateTime.utc(2026, 6, 29, 15, 7));
      final idx = lastBotIndex();
      await chat!.selectSwipe(idx, 0);
      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(
        chat!.timeService.clock,
        first,
        reason: 'never subtract the 2 hr chip from a later swipe clock',
      );
    },
  );

  test('new swipes A=30 and B=5: swipe sets each slot clock', () async {
    await boot();
    llm.nextMinutes = 30;
    await chat!.sendMessage('Hey.');
    await drainTurn();
    final beforeIso =
        lastBot().activeMetadata?['story_clock_before'] as String?;
    expect(beforeIso, isNotNull);
    final before = DateTime.parse(beforeIso!);
    expect(
      lastBot().activeMetadata?['story_clock_after'],
      chat!.timeService.storyClockIso,
    );
    expect(chat!.timeService.clock, before.add(const Duration(minutes: 30)));

    llm.nextMinutes = 5;
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, before.add(const Duration(minutes: 5)));
    expect(lastBot().swipes.length, greaterThanOrEqualTo(2));
    expect(
      lastBot().swipeMetadata[0]?['story_clock_after'],
      StoryClock.serializeClock(before.add(const Duration(minutes: 30))),
    );
    expect(
      lastBot().swipeMetadata[1]?['story_clock_after'],
      StoryClock.serializeClock(before.add(const Duration(minutes: 5))),
    );
    for (final slot in lastBot().swipeMetadata) {
      expect(slot?['story_clock_before'], beforeIso);
    }
    expect(lastBot().metadata?['story_clock_before'], beforeIso);

    final idx = lastBotIndex();
    await chat!.selectSwipe(idx, 0);
    expect(
      chat!.timeService.clock,
      before.add(const Duration(minutes: 30)),
      reason: 'swipe A applies that slot after, not the live B clock',
    );
    await chat!.selectSwipe(idx, 1);
    expect(chat!.timeService.clock, before.add(const Duration(minutes: 5)));

    llm.nextMinutes = 30;
    await chat!.sendMessage('And then?');
    await drainTurn();
    expect(
      chat!.timeService.clock,
      before.add(const Duration(minutes: 35)),
      reason: 'next send ticks from the selected B after',
    );
  });

  test('failed regen leaves the clock unchanged', () async {
    await boot();
    await plantOldTranscript();
    llm.nextMinutes = 30;
    await chat!.regenerateLastMessage();
    await drainTurn();
    final accepted = chat!.timeService.clock;
    llm.failNextChat = true;
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, accepted);
  });

  test('cancelled-during-eval regen leaves the clock unchanged', () async {
    await boot();
    await plantOldTranscript();
    await chat!.regenerateLastMessage();
    await drainTurn();
    final accepted = chat!.timeService.clock;
    llm.cancelNextEval = true;
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, accepted);
  });

  test('delete greeting (non-tail) leaves the live clock alone', () async {
    await boot();
    await plantOldTranscript();
    expect(chat!.timeService.clock, _lived);
    // Greeting at index 0 carries a Day 1 09:00 snap. Deleting it must
    // not restore that snap onto the live clock. Mid-chat delete is
    // pinned in clock_hold_spec_test.
    chat!.deleteMessage(0);
    await drainTurn();
    expect(
      chat!.timeService.clock,
      _lived,
      reason:
          'non-tail delete must not take the new last message\'s '
          'realism_state.storyClock (old chats freeze that at Day 1 09:00)',
    );
  });

  test('delete tail rewinds to the shared before', () async {
    await boot();
    await plantOldTranscript();
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 17, 7));
    chat!.deleteMessage(lastBotIndex());
    await drainTurn();
    expect(chat!.timeService.clock, _lived);
  });

  test('group per-speaker cancel leaves the clock unchanged', () async {
    await boot();
    await db!.insertGroup(
      GroupsCompanion.insert(id: 'grp-clk', name: 'The Porch'),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-nia',
        groupId: 'grp-clk',
        name: 'Nia',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-nia.png'),
      ),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: 'grp-clk',
        name: 'Bea',
        firstMessage: const Value('Hi.'),
        avatarFilename: const Value('mem-bea.png'),
      ),
    );
    await chat!.setActiveGroup(
      GroupChat(id: 'grp-clk', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    await chat!.setRealismEnabled(true);
    await drainTurn();
    await chat!.sendMessage('Hey you two.');
    await drainTurn();
    final accepted = chat!.timeService.clock;
    llm.cancelNextEval = true;
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, accepted);
  });

  test('1:1 fork at a Day-1 message of a Day-3 chat uses the stamp', () async {
    await boot();
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    final greetingMeta = jsonEncode({
      'realism_state': _day1NineSnap,
      'story_clock_before': _day1NineIso,
      'story_clock_after': _day1NineIso,
    });
    final day1Meta = jsonEncode({
      'realism_state': _day1NineSnap,
      'story_clock_before': _day1NineIso,
      'story_clock_after': _day1NineThirtyIso,
      'time_passed': '30 min',
    });
    final day3Meta = jsonEncode({
      'realism_state': _day3Snap,
      'story_clock_before': _day3Iso,
      'story_clock_after': _day3Iso,
    });
    await db!.deleteMessagesForSession(sid);
    Future<void> insert({
      required String id,
      required int position,
      required String sender,
      required bool isUser,
      required String text,
      String? meta,
    }) {
      return db!.insertMessage(
        MessagesCompanion.insert(
          id: id,
          sessionId: sid,
          position: position,
          sender: sender,
          isUser: isUser,
          swipes: Value(jsonEncode([text])),
          metadata: Value(meta),
          swipeMetadata: Value(
            meta == null ? null : jsonEncode([jsonDecode(meta)]),
          ),
        ),
      );
    }

    await insert(
      id: 'fork-g',
      position: 0,
      sender: 'Nia',
      isUser: false,
      text: 'Morning.',
      meta: greetingMeta,
    );
    await insert(
      id: 'fork-u1',
      position: 1,
      sender: 'You',
      isUser: true,
      text: 'Hi.',
    );
    await insert(
      id: 'fork-b1',
      position: 2,
      sender: 'Nia',
      isUser: false,
      text: 'Coffee?',
      meta: day1Meta,
    );
    await insert(
      id: 'fork-u2',
      position: 3,
      sender: 'You',
      isUser: true,
      text: 'Later.',
    );
    await insert(
      id: 'fork-b2',
      position: 4,
      sender: 'Nia',
      isUser: false,
      text: 'Three days on.',
      meta: day3Meta,
    );
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        passageOfTimeEnabled: const Value(true),
        passageOfTimeGateMigrated: const Value(true),
        storyClock: const Value(_day3Iso),
        storyStartDate: const Value(_startIso),
        timeOfDay: const Value('afternoon'),
        dayCount: const Value(3),
      ),
    );
    await chat!.reloadCurrentSession();
    await drainTurn();
    expect(chat!.timeService.clock, _day3);

    await chat!.forkFromMessage(2);
    await drainTurn();
    expect(
      chat!.timeService.clock,
      _day1NineThirty,
      reason: 'fork uses stamped after, not the Day-3 snap or live clock',
    );
  });

  test('Day-1 rewind pulls the start date so dayCount stays 1', () async {
    await boot();
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    final dawnIso = '2026-06-28T00:10:00.000Z';
    final lastMeta = jsonEncode({
      'realism_state': {
        ..._day1NineSnap,
        'storyClock': dawnIso,
        'dayCount': 1,
        'timeOfDay': 'night',
      },
      'time_passed': '30 min',
    });
    await db!.deleteMessagesForSession(sid);
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'floor-g',
        sessionId: sid,
        position: 0,
        sender: 'Nia',
        isUser: false,
        swipes: Value(jsonEncode(['Evening.'])),
        metadata: Value(jsonEncode({'realism_state': _day1NineSnap})),
        swipeMetadata: Value(
          jsonEncode([
            {'realism_state': _day1NineSnap},
          ]),
        ),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'floor-b',
        sessionId: sid,
        position: 1,
        sender: 'Nia',
        isUser: false,
        swipes: Value(jsonEncode(['Almost midnight.'])),
        metadata: Value(lastMeta),
        swipeMetadata: Value(jsonEncode([jsonDecode(lastMeta)])),
      ),
    );
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        passageOfTimeEnabled: const Value(true),
        passageOfTimeGateMigrated: const Value(true),
        storyClock: Value(dawnIso),
        storyStartDate: const Value(_startIso),
        timeOfDay: const Value('night'),
        dayCount: const Value(1),
      ),
    );
    await chat!.reloadCurrentSession();
    await drainTurn();
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 28, 0, 10));
    chat!.deleteMessage(lastBotIndex());
    await drainTurn();
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 27, 23, 40));
    expect(chat!.timeService.dayCount, 1);
    expect(chat!.timeService.startDate, DateTime.utc(2026, 6, 27));
  });

  test('Porch Life OFF leaves the clock unchanged on regen', () async {
    await boot(porchLife: false);
    await plantOldTranscript();
    expect(chat!.timeService.passageOfTimeEnabled, isFalse);
    await chat!.regenerateLastMessage();
    await drainTurn();
    expect(chat!.timeService.clock, _lived);
    expect(lastBot().activeMetadata?['story_clock_after'], isNull);
  });
}
