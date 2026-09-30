// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// B: _writeSlotClock never stores an inverted pair. If after is
// earlier than before, it stores before = after, for every kind.
// Pairs are read from message metadata keys, not only the resolver.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show StoryClock, resolveSlotAfter, slotClockAfter, slotClockBefore;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_writer_pair_').path;
        }
        return null;
      });
}

final _at0730 = DateTime.utc(2026, 6, 28, 7, 30);
final _at0800 = DateTime.utc(2026, 6, 28, 8, 0);
final _at0815 = DateTime.utc(2026, 6, 28, 8, 15);
final _at0830 = DateTime.utc(2026, 6, 28, 8, 30);
final _at0900 = DateTime.utc(2026, 6, 28, 9, 0);

class _ScriptedLlm extends LLMService {
  String reply = 'It is 7:30 a.m. on the porch.';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield reply;
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 0, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'WriterPair';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
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
    db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    final repo = CharacterRepository(db!, storage);
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db!),
            storage,
            WorldRepository(storage, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Morning.',
      imagePath: '/tmp/nia-writer-pair.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
  }

  ChatMessage tip() =>
      chat!.messages.lastWhere((m) => !m.isUser && m.sender != 'System');

  void expectStoredPair(DateTime clock, {required String reason}) {
    final iso = StoryClock.serializeClock(clock);
    final meta = tip().metadata ?? tip().activeMetadata;
    expect(meta, isNotNull, reason: '$reason — metadata present');
    expect(
      meta!['story_clock_before'],
      iso,
      reason: '$reason — stored before key == $iso',
    );
    expect(
      meta['story_clock_after'],
      iso,
      reason: '$reason — stored after key == $iso',
    );
    expect(slotClockBefore(meta), clock, reason: '$reason — parsed before');
    expect(slotClockAfter(meta), clock, reason: '$reason — parsed after');
    expect(
      resolveSlotAfter(meta, isTip: true, liveClock: chat!.timeService.clock),
      clock,
      reason: '$reason — resolved stays $clock, not clamped back up',
    );
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('backward nudge stores before = after = the nudged clock', () async {
    await boot();
    await chat!.setStoryClock(_at0900);
    await drain();
    expectStoredPair(_at0900, reason: 'setup 09:00');

    await chat!.nudgeTimePeriod(-1);
    await drain();
    expect(chat!.timeService.clock, _at0830);
    expectStoredPair(
      _at0830,
      reason:
          'backward 30-min nudge from 09:00 lands 08:30/08:30 '
          '(not 09:00/08:30)',
    );
  });

  test('backward skip-to stores before = after = the skip target', () async {
    await boot();
    await chat!.setStoryClock(_at0900);
    await drain();

    await chat!.setStoryClock(_at0815);
    await drain();
    expect(chat!.timeService.clock, _at0815);
    expectStoredPair(
      _at0815,
      reason: 'backward skip-to 08:15 stores 08:15/08:15, not 09:00/08:15',
    );
  });

  test(
    'named reconcile earlier than stored before writes 07:30/07:30',
    () async {
      await boot();
      await chat!.setStoryClock(_at0800);
      await drain();
      llm.reply = 'It is 7:30 a.m. on the porch.';
      await chat!.sendMessage('What time is it?');
      await drain();
      expect(chat!.timeService.clock, _at0730);
      expectStoredPair(
        _at0730,
        reason:
            'named 07:30 from an 08:00 before stores 07:30/07:30 '
            'in message metadata',
      );
    },
  );
}
