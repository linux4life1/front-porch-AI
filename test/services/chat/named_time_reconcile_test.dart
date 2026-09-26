// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// K-A: a named reconcile overwrites the slot's own before, so the
// pair is 07:30/07:30 and the clamp still holds — the clamp never
// beats a named story time. Live, sidebar, and the next prompt
// read 07:30. Continue goes through _writeSlotClock the same way
// and survives swipe away/back and reopen.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show TimeService, slotClockAfter, slotClockBefore;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_named_time_').path;
        }
        return null;
      });
}

final _at0730 = DateTime.utc(2026, 6, 28, 7, 30);
final _at0800 = DateTime.utc(2026, 6, 28, 8, 0);

class _ScriptedLlm extends LLMService {
  String reply = 'It is 7:30 a.m. on the porch.';
  final prompts = <String>[];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield reply;
      return;
    }
    prompts.add(params.prompt);
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
  String get backendName => 'NamedTime';
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
    db = AppDatabase.forTesting();
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
      imagePath: '/tmp/nia-named-time.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
    await chat!.setStoryClock(_at0800);
    await drain();
  }

  ChatMessage lastBot() =>
      chat!.messages.lastWhere((m) => !m.isUser && m.sender != 'System');

  void expectSevenThirty({required String reason}) {
    expect(chat!.timeService.clock, _at0730, reason: reason);
    expect(chat!.timeService.displayClock, '7:30 AM', reason: reason);
    expect(
      TimeService.postureQuestion(charName: 'Nia', displayClock: '7:30 AM'),
      contains('Current time: 7:30 AM'),
    );
    final before = slotClockBefore(lastBot().activeMetadata);
    final after = slotClockAfter(lastBot().activeMetadata);
    expect(before, _at0730, reason: '$reason — stored before == 07:30');
    expect(after, _at0730, reason: '$reason — stored after == 07:30');
    expect(
      before,
      after,
      reason: '$reason — named overwrite; pair is 07:30/07:30',
    );
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('named 7:30 a.m. from an 08:00 tip moves live, sidebar, pair', () async {
    await boot();
    expect(chat!.timeService.clock, _at0800);
    await chat!.sendMessage('What time is it?');
    await drain();
    expectSevenThirty(reason: 'send that names 7:30 a.m.');

    llm.reply = 'Another swipe.';
    await chat!.regenerateLastMessage();
    await drain();
    final swipeIdx = chat!.messages.indexOf(lastBot());
    await chat!.swipeMessage(swipeIdx, -1);
    await drain();
    expectSevenThirty(reason: 'swipe away and back keeps 07:30');

    llm.reply = '*Nia nods at the clock.*';
    llm.prompts.clear();
    await chat!.sendMessage('Still morning?');
    await drain();
    expect(
      llm.prompts.any((p) => p.contains('7:30 AM') || p.contains('7:30')),
      isTrue,
      reason: 'the next prompt clock line reads 07:30',
    );

    final sid = chat!.currentSessionId!;
    await chat!.loadSession(sid);
    await drain();
    expectSevenThirty(reason: 'reopen keeps 07:30');
  });

  test(
    'Continue named-time reconcile survives swipe away/back and reload',
    () async {
      await boot();
      llm.reply = '*Nia leans on the rail.*';
      await chat!.sendMessage('Hey.');
      await drain();
      await chat!.setStoryClock(_at0800);
      await drain();

      llm.reply = 'It is 7:30 a.m. now.';
      await chat!.continueGeneration();
      await drain();
      expectSevenThirty(reason: 'Continue applyReconciledClock');

      llm.reply = 'Another swipe.';
      await chat!.regenerateLastMessage();
      await drain();
      final swipeIdx = chat!.messages.indexOf(lastBot());
      await chat!.swipeMessage(swipeIdx, -1);
      await drain();
      expectSevenThirty(reason: 'swipe away and back keeps 07:30');

      await chat!.loadSession(chat!.currentSessionId!);
      await drain();
      expectSevenThirty(reason: 'reload after Continue keeps 07:30');

      llm.reply = '*Nia nods at the clock.*';
      llm.prompts.clear();
      await chat!.sendMessage('Still morning?');
      await drain();
      expect(
        llm.prompts.any((p) => p.contains('7:30 AM') || p.contains('7:30')),
        isTrue,
        reason: 'the next prompt after Continue reopen reads 07:30',
      );
    },
  );
}
