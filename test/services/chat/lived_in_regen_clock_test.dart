// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regen of an old last bot must rewind to the PRE-REPLY time, never a
// frozen realism_state clock snap. Synthetic transcript shaped like a
// lived-in chat: no story_clock_before, every snap Day 1 09:00, session
// clock Day 2 16:37.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lived_clock_').path;
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
final _lived = DateTime.utc(2026, 6, 29, 16, 37);

const _day1NineSnap = {
  'timeOfDay': 'morning',
  'dayCount': 1,
  'storyClock': _day1NineIso,
  'storyStartDate': _startIso,
  'characterEmotion': 'neutral',
  'emotionIntensity': 'mild',
};

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
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
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*Nia leans on the rail.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLivedInRegenClock';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;

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
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!)
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage!.initialized;

    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-lived-clock.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: false,
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
        id: 'lived-old-g',
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
        id: 'lived-old-u',
        sessionId: sid,
        position: 1,
        sender: 'You',
        isUser: true,
        swipes: Value(jsonEncode(['Hey.'])),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'lived-old-b',
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
        passageOfTimeEnabled: const Value(false),
        passageOfTimeGateMigrated: const Value(false),
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

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

  test('minutesFromTimePassed reads chip text only', () {
    expect(minutesFromTimePassed('5 min'), 5);
    expect(minutesFromTimePassed('30 min'), 30);
    expect(minutesFromTimePassed('1 hr'), 60);
    expect(minutesFromTimePassed('2 hr 5 min'), 125);
    expect(minutesFromTimePassed('same moment'), 0);
    expect(minutesFromTimePassed('Next morning'), isNull);
    expect(minutesFromTimePassed(5), isNull);
    expect(minutesFromTimePassed(null), isNull);
    expect(minutesRecordedForClockRewind({'time_passed': '5 min'}), 5);
    expect(minutesRecordedForClockRewind({'minutes': 12}), isNull);
    expect(minutesRecordedForClockRewind({'minutes_elapsed': 8}), isNull);
  });

  test(
    'rewindToBeforeIso sets the clock, or keeps live when before is null',
    () {
      var porch = true;
      final t = TimeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        onPatchLastMessageRealismState: (_, _, _) {},
        getPorchLifePassageOfTime: () => porch,
      );
      t.seedFromV2OrExt(
        dayCount: 2,
        timeOfDay: 'afternoon',
        storyStartDate: _startIso,
        storyStartTime: '16:37',
      );
      expect(t.clock, _lived);

      t.rewindToBeforeIso(_day1NineIso);
      expect(t.clock, DateTime.utc(2026, 6, 28, 9, 0));

      t.restoreTimeFromRealismState({'storyClock': _livedIso});
      t.rewindToBeforeIso(null);
      expect(t.clock, _lived);

      t.markClockGateLeftover(false);
      expect(t.clockGateSource, contains('leftover=false'));
      expect(t.clockGateSource, contains('porchLife=true'));
      porch = false;
      expect(t.clockGateSource, contains('porchLife=false'));
      expect(t.clockGateSource, isNot(contains('porchLife=true')));
    },
  );

  test(
    'regen of an old last bot keeps Day 2 16:37, never Day 1 09:00',
    () async {
      await boot();
      await plantOldTranscript();
      expect(
        lastBot().activeMetadata?['story_clock_before'],
        isNotNull,
        reason: 'one-path backfill fills the pair from the live clock',
      );

      await chat!.regenerateLastMessage();
      await drainTurn();

      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 29, 17, 7),
        reason:
            'no story_clock_before: keep the live session clock (16:37) '
            'and add the new minutes. A Day 1 09:00 snap is not pre-reply.',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );

  test(
    'regen of an old last bot with time_passed=5 rewinds five then adds',
    () async {
      await boot();
      await plantOldTranscript(timePassed: '5 min');
      expect(
        lastBot().activeMetadata?['story_clock_before'],
        isNotNull,
        reason: 'one-path backfill fills the pair from live minus chip minutes',
      );
      expect(lastBot().activeMetadata?['time_passed'], '5 min');

      await chat!.regenerateLastMessage();
      await drainTurn();

      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 29, 17, 2),
        reason:
            'no before, time_passed=5: rewind the live 16:37 by 5, then '
            'add the new 30 (17:02). Never Day 1 09:00.',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );

  test('[Clock] source follows a live Porch Life OFF', () async {
    await boot();
    await plantOldTranscript();
    expect(chat!.timeService.clockGateSource, contains('leftover=false'));
    expect(chat!.timeService.clockGateSource, contains('porchLife=true'));

    await storage!.realismSettings.setPassageOfTimeDefault(false);
    expect(chat!.timeService.passageOfTimeEnabled, isFalse);
    expect(
      chat!.timeService.clockGateSource,
      contains('porchLife=false'),
      reason:
          'source must read the live Porch Life value, not the leftover '
          'string baked at hydrate',
    );
    expect(
      chat!.timeService.clockGateSource,
      isNot(contains('porchLife=true')),
    );
  });
}
