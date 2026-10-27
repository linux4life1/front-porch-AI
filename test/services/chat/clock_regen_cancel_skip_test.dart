// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regen holds: a cancel during the pre-reply judges keeps the reply and
// says so, and a regen of an OOC skip keeps the skip clock and label.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/skip_reader_answers.dart';

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

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  String nextReply = '*Nia leans on the rail.*';
  bool cancelOnEval = false;
  Future<void> Function()? cancel;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final skip = skipReaderReply(params.prompt);
    if (skip != null) {
      yield skip;
      return;
    }
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
