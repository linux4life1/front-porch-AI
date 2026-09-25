// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Open-path pin: a brand-new chat with a date-only start and no card
// storyStartTime opens at Day 1 09:00. A card storyStartTime is
// honoured. Resolver ladder rung 8 already covers a non-tip empty
// greeting → Day 1 09:00.

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
          return Directory.systemTemp.createTempSync('fpai_open_day1_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentOpeningDay1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;

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

  Future<ChatService> openCard({
    String? storyStartTime,
    String firstMessage = 'Morning.',
  }) async {
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
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db!),
            storage,
            WorldRepository(storage, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: firstMessage,
      imagePath: '/tmp/nia-open-day1.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: true,
        storyStartDate: '2026-06-28',
        storyStartTime: storyStartTime,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
    return chat!;
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'new chat, date-only start, no card time opens at Day 1 09:00',
    () async {
      await openCard();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 28, 9, 0),
        reason: 'brand-new chat with no storyStartTime opens 06-28 09:00',
      );
      expect(chat!.timeService.dayCount, 1);
      expect(chat!.timeService.startDate, DateTime.utc(2026, 6, 28));
    },
  );

  test('new chat honours card storyStartTime', () async {
    await openCard(storyStartTime: '16:37');
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 28, 16, 37),
      reason: 'card storyStartTime 16:37 is the opening clock',
    );
  });

  test('empty greeting, date-only start opens at Day 1 09:00', () async {
    await openCard(firstMessage: '');
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 28, 9, 0),
      reason: 'empty greeting with no card time stays Day 1 09:00',
    );
  });
}
