// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat settings Automatic Passage of Time is the live clock gate.
// The toggle must exist and flip the same field _clockRunning reads.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_settings.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pot_toggle_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*She nods.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedPotToggle';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  testWidgets(
    'chat-settings Automatic Passage of Time exists and flips the clock gate',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'passage_of_time_default': true,
      });
      final db = AppDatabase.forTesting();
      final storage = StorageService();
      final repo = CharacterRepository(db, storage);
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(repo)
            ..testLlmServiceOverride = _ScriptedLlm();
      addTearDown(() async {
        chat.dispose();
        await db.close();
      });
      await storage.initialized;

      final carmen = CharacterCard(
        name: 'Carmen',
        firstMessage: 'Evening.',
        imagePath: '/tmp/carmen-pot-toggle.png',
        frontPorchExtensions: FrontPorchExtensions(passageOfTimeEnabled: true),
      );
      await repo.addCharacter(carmen);
      await chat.setActiveCharacter(carmen);
      await chat.setPassageOfTimeEnabled(true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: chat,
                builder: (_, _) =>
                    CharacterStateSettings(chat: chat, isGroup: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Automatic Passage of Time'), findsOneWidget);
      expect(chat.timeService.passageOfTimeEnabled, isTrue);

      final potSwitch = find.byType(Switch).first;
      await tester.tap(potSwitch);
      await tester.pumpAndSettle();

      expect(
        chat.timeService.passageOfTimeEnabled,
        isFalse,
        reason: 'the visible switch writes the same field _clockRunning reads',
      );

      await chat.sendMessage('How are you?');
      for (
        var i = 0;
        i < 400 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await tester.pump(Duration.zero);
      }
      expect(
        chat.messages
            .lastWhere((m) => !m.isUser)
            .activeMetadata?['time_passed'],
        isNull,
        reason: 'Off must gate the clock — no minutes chip',
      );

      await tester.tap(potSwitch);
      await tester.pumpAndSettle();
      expect(chat.timeService.passageOfTimeEnabled, isTrue);

      final before = chat.timeService.clock;
      await chat.sendMessage('Still there?');
      for (
        var i = 0;
        i < 400 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await tester.pump(Duration.zero);
      }
      expect(chat.timeService.clock.difference(before).inMinutes, 30);
      expect(
        chat.messages
            .lastWhere((m) => !m.isUser)
            .activeMetadata?['time_passed'],
        '30 min',
      );
    },
  );
}
