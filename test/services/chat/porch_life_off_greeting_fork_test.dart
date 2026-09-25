// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life OFF: forking at the greeting writes no clock stamps and
// runs no seeded passage-of-time (zero time LLM calls, no story_clock
// fields, no time chip).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pot_off_fork_').path;
        }
        return null;
      });
}

class _CountingLlm extends LLMService {
  int timeCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      timeCalls++;
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield 'Evening.';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'CountTimeOffFork';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'Porch Life OFF fork at greeting writes no stamps and no time LLM',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
        'passage_of_time_default': false,
      });
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final storage = StorageService();
      final repo = CharacterRepository(db, storage);
      final llm = _CountingLlm();
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(repo)
            ..testLlmServiceOverride = llm;
      addTearDown(chat.dispose);
      await storage.initialized;
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        imagePath: '/tmp/nia-pot-off-fork.png',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );
      await repo.addCharacter(nia);
      await chat.setActiveCharacter(nia);
      for (var i = 0; i < 40 && chat.messages.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(chat.messages, isNotEmpty);
      expect(chat.messages.first.isUser, isFalse);
      expect(chat.timeService.passageOfTimeEnabled, isFalse);
      final timeCallsBeforeFork = llm.timeCalls;

      await chat.forkFromMessage(0);

      expect(
        llm.timeCalls,
        timeCallsBeforeFork,
        reason: 'fork at greeting with Porch Life OFF must not seed a time LLM',
      );
      expect(llm.timeCalls, 0);
      for (final msg in chat.messages) {
        final slot = msg.activeMetadata;
        expect(
          slot?['story_clock_before'],
          isNull,
          reason: 'Porch Life OFF greeting fork writes no clock stamps',
        );
        expect(slot?['story_clock_after'], isNull);
        expect(slot?['time_passed'], isNull);
      }
    },
  );
}
