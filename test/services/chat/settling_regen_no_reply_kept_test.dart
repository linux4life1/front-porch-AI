// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regen and swipe-right during a settling turn must not show
// 'Reply kept…' — the user asked for a new reply, not to keep the old one.

import 'dart:async';
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
          return Directory.systemTemp.createTempSync('fpai_settle_kept_').path;
        }
        return null;
      });
}

class _HangClockLlm extends LLMService {
  Completer<void>? _hang;
  int clockCalls = 0;

  void release() {
    final hang = _hang;
    if (hang != null && !hang.isCompleted) hang.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia leans on the rail.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      clockCalls++;
      if (clockCalls == 1) {
        _hang = Completer<void>();
        await _hang!.future;
      }
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.prompt.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SettleNoKept';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;
  late _HangClockLlm llm;

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

  Future<void> waitUntil(bool Function() pred) async {
    for (var i = 0; i < 250 && !pred(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
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
    llm = _HangClockLlm();
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
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-settle-kept.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('regen during a settling turn does not show Reply kept', () async {
    await boot();
    final sent = chat!.sendMessage('Hey.');
    await waitUntil(() => llm.clockCalls >= 1 && chat!.isSettlingTurn);
    expect(chat!.isSettlingTurn, isTrue);
    final regen = chat!.regenerateLastMessage();
    llm.release();
    await sent;
    await regen;
    await drain();
    expect(
      chat!.guestActivityStatus ?? '',
      isNot(contains('Reply kept')),
      reason: 'regen during settle is a new reply, not a keep',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('swipe-right during a settling turn does not show Reply kept', () async {
    await boot();
    final sent = chat!.sendMessage('Hey.');
    await waitUntil(() => llm.clockCalls >= 1 && chat!.isSettlingTurn);
    expect(chat!.isSettlingTurn, isTrue);
    final tip = chat!.messages.lastWhere((m) => !m.isUser);
    final swipe = chat!.swipeMessage(chat!.messages.indexOf(tip), 1);
    llm.release();
    await sent;
    await swipe;
    await drain();
    expect(
      chat!.guestActivityStatus ?? '',
      isNot(contains('Reply kept')),
      reason: 'swipe-right during settle must not claim the reply was kept',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
