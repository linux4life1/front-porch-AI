// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AFK period advance must stamp time_skip_to and a chip that names
// the sidebar span, not 'same moment'. Regen of that AFK reply keeps
// both.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_afk_skip_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia watches the street.*';
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
  String get backendName => 'AfkSkipChip';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;
  StorageService? storage;

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
    final repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage!.initialized;
    await storage!.generationSettings.setDynamicResponses(true);
    await storage!.generationSettings.setDynamicResponsePacePeriods(1);
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-afk-skip.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
  }

  ChatMessage lastBot() =>
      chat!.messages.lastWhere((m) => !m.isUser && m.sender != 'System');

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('AFK period advance stamps time_skip_to and a span chip', () async {
    await boot();
    await chat!.sendMessage('I will be back.');
    await drain();
    chat!.debugFireIdleTimerForTest();
    await drain();
    final afk = lastBot();
    final skipTo = afk.activeMetadata?['time_skip_to'] as String?;
    final chip = afk.activeMetadata?['time_passed'] as String?;
    expect(skipTo, isNotNull, reason: 'AFK must stamp time_skip_to');
    expect(skipTo, isNotEmpty);
    expect(chip, isNotNull);
    expect(chip, isNot('same moment'));
    expect(
      chip,
      chat!.timeService.bodyTimeLabel,
      reason: 'AFK chip must match the sidebar span',
    );
  });

  test('AFK regen keeps time_skip_to and the chip', () async {
    await boot();
    await chat!.sendMessage('I will be back.');
    await drain();
    chat!.debugFireIdleTimerForTest();
    await drain();
    final skipTo = lastBot().activeMetadata?['time_skip_to'];
    final chip = lastBot().activeMetadata?['time_passed'];
    expect(skipTo, isNotNull);
    await chat!.regenerateLastMessage();
    await drain();
    expect(lastBot().activeMetadata?['time_skip_to'], skipTo);
    expect(lastBot().activeMetadata?['time_passed'], chip);
  });
}
