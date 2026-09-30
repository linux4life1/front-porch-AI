// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SecurityBot / Senior Dev / UI Champion follow-up pins for #303.

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

import 'time_service_test.dart' show makeService, runEval, seedFixed;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_fu_').path;
        }
        return null;
      });
}

ChatMessage _bot(String text, Map<String, dynamic> meta) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: Map<String, dynamic>.from(meta),
  );
}

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  String nextReply = '*Nia leans on the rail.*';
  bool cancelOnEval = false;
  Future<void> Function()? cancel;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield nextReply;
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta') || p.contains('emotion_intensity')) {
      if (cancelOnEval) {
        cancelOnEval = false;
        await cancel?.call();
        return;
      }
    }
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
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedFollowup';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('nearestReal prefers an earlier stamp over a closer later one', () {
    final earlier = _bot('nine-thirty', {
      'story_clock_before': '2026-06-28T09:30:00.000Z',
      'story_clock_after': '2026-06-28T09:30:00.000Z',
    });
    final mid = _bot('unstamped', {});
    final later = _bot('evening', {
      'story_clock_before': '2026-06-28T18:00:00.000Z',
      'story_clock_after': '2026-06-28T18:00:00.000Z',
    });
    backfillSlotClocks(
      [
        earlier,
        ChatMessage(text: 'ok', sender: 'You', isUser: true),
        mid,
        later,
      ],
      liveClock: DateTime.utc(2026, 6, 28, 18, 0),
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(
      slotClockAfter(mid.metadata),
      DateTime.utc(2026, 6, 28, 9, 30),
      reason: 'pos 2 must take earlier 09:30, not closer later 18:00',
    );
  });

  test('K-2: null swipe slot above 0 is not created as a bare map', () {
    final msg = ChatMessage(
      text: 'A',
      sender: 'Nia',
      isUser: false,
      metadata: {
        'is_dream': true,
        'realism_state': {'trustLevel': 45},
      },
      swipes: const ['A', 'B'],
      swipeMetadata: [null, null],
      swipeIndex: 1,
    );
    backfillSlotClocks(
      [msg],
      liveClock: DateTime.utc(2026, 6, 30, 16, 0),
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(msg.swipeMetadata[1], isNull);
    expect(msg.metadata?['story_clock_after'], isNotNull);
    expect(msg.activeMetadata?['is_dream'], isTrue);
  });

  test('named-time reconcile re-notes a counted chip', () async {
    final t = makeService();
    seedFixed(t, timeOfDay: 'morning');
    await runEval(t, oneShotText: '{"minutes_elapsed": 30, "new_day": false}');
    expect(t.bodyTimeLabel, '30 min');
    final named = t.clock.add(const Duration(hours: 2));
    await t.applyReconciledClock(named);
    expect(t.clock, named);
    expect(
      t.bodyTimeLabel,
      '2 hr 30 min',
      reason: 'chip must equal sidebar delta after a 2h named-time correction',
    );
  });

  test(
    'named-time reconcile leaves Next morning and skip labels alone',
    () async {
      final t = makeService();
      seedFixed(t, timeOfDay: 'night');
      await runEval(
        t,
        oneShotText: '{"minutes_elapsed": 0, "new_day": true}',
        recent: 'User: good night\nNia: sleep well, see you in the morning',
      );
      expect(t.bodyTimeLabel, 'Next morning');
      await t.applyReconciledClock(t.clock.add(const Duration(hours: 1)));
      expect(t.bodyTimeLabel, 'Next morning');
    },
  );

  test('stall backstop chip is the snap delta, not same moment', () async {
    final t = makeService();
    seedFixed(t, timeOfDay: 'morning');
    for (var i = 0; i < StoryClock.stallBackstopTurns; i++) {
      await runEval(
        t,
        oneShotText:
            '{"minutes_elapsed": 0, "new_day": false, '
            '"continuous_instant": true}',
      );
    }
    expect(t.clock, DateTime.utc(2026, 7, 2, 11, 30));
    expect(
      t.bodyTimeLabel,
      timePassedLabel(
        minutes: DateTime.utc(
          2026,
          7,
          2,
          11,
          30,
        ).difference(DateTime.utc(2026, 7, 2, 9, 0)).inMinutes,
        nextMorning: false,
        isSkip: false,
      ),
      reason: 'stall snap must not stamp same moment',
    );
  });

  group('v1.4 pos 2 greetingClock', () {
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
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<void> bootFixture() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final dir = Directory.systemTemp.createTempSync('fpai_fu_v14_');
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
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    test('Clocked pos 2 is 09:30, not later 18:00', () async {
      await bootFixture();
      final card = repo!.characters.firstWhere((c) => c.name == 'Clocked');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314133694');
      await drain();
      final pos2 = chat!.messages[2];
      expect(
        slotClockAfter(pos2.activeMetadata) ?? slotClockAfter(pos2.metadata),
        DateTime.utc(2026, 9, 25, 9, 30),
        reason: 'v14 Clocked pos 2 must not land on 09-28 18:00',
      );
    });

    test('HostOn pos 2 is 09:30, not 10:00', () async {
      await bootFixture();
      final card = repo!.characters.firstWhere((c) => c.name == 'HostOn');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314131886');
      await drain();
      final pos2 = chat!.messages[2];
      expect(
        slotClockAfter(pos2.activeMetadata) ?? slotClockAfter(pos2.metadata),
        DateTime.utc(2026, 9, 25, 9, 30),
        reason: 'v14 HostOn pos 2 must not land on 10:00',
      );
    });

    test('paged-window Clocked pos 2 stays 09:30', () async {
      await bootFixture();
      final card = repo!.characters.firstWhere((c) => c.name == 'Clocked');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314133694');
      await drain();
      final sid = chat!.currentSessionId!;
      final n = chat!.messages.length;
      for (var i = 0; i < 30; i++) {
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'pad$i',
            sessionId: sid,
            position: n + i,
            sender: i.isEven ? 'You' : 'Clocked',
            isUser: i.isEven,
            swipes: Value(jsonEncode(['pad $i'])),
            metadata: Value(
              i.isEven
                  ? null
                  : jsonEncode({
                      'story_clock_before': '2026-09-28T18:00:00.000Z',
                      'story_clock_after': '2026-09-28T18:00:00.000Z',
                    }),
            ),
          ),
        );
      }
      await chat!.reloadCurrentSession();
      await drain();
      expect(chat!.messages.length, greaterThan(24));
      final pos2 = chat!.messages[2];
      expect(
        slotClockAfter(pos2.activeMetadata) ?? slotClockAfter(pos2.metadata),
        DateTime.utc(2026, 9, 25, 9, 30),
        reason: 'window guess must not move archive pos 2 to tail 18:00',
      );
    });
  });

  group('regen cancel + skip', () {
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
        firstMessage: 'Hi.',
        imagePath: '/tmp/nia-fu.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          passageOfTimeEnabled: true,
        ),
      );
      await repo!.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await drain();
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    test(
      'regen cancel during pre-reply judges keeps the reply banner',
      () async {
        await boot();
        llm.nextMinutes = 30;
        await chat!.sendMessage('Hey.');
        await drain();
        expect(chat!.messages.where((m) => !m.isUser).length, 2);
        llm.cancelOnEval = true;
        await chat!.regenerateLastMessage();
        await drain();
        expect(
          chat!.guestActivityStatus,
          contains('Reply kept. Scene time and needs weren\'t updated.'),
        );
        expect(chat!.guestActivityStatus, isNot(contains('or send again')));
        expect(chat!.messages.where((m) => !m.isUser).length, 2);
      },
    );

    test('regen of a skip keeps the skip clock and label', () async {
      await boot();
      await chat!.sendMessage('(ooc: skip ahead two hours)');
      await drain();
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      final skipTo = last.activeMetadata?['time_skip_to'] as String?;
      final after = last.activeMetadata?['story_clock_after'];
      final clock = chat!.timeService.clock;
      expect(skipTo, isNotNull);
      llm.nextMinutes = 30;
      await chat!.regenerateLastMessage();
      await drain();
      final again = chat!.messages.lastWhere((m) => !m.isUser);
      expect(chat!.timeService.clock, clock);
      expect(again.activeMetadata?['story_clock_after'], after);
      expect(again.activeMetadata?['time_skip_to'], skipTo);
    });
  });
}
