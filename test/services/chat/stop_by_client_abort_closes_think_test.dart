// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stop on an HTTP backend closes the client, so the stream THROWS instead of
// ending: the turn leaves through the catch path's treatAsCancel, not the
// stream-loop break. That path must salvage the cut thought the same way:
// keep the partial, store the closer, no error banner.
//
// Proven red: pass a null target from the catch path to _haltStoppedTurn
// (the old behaviour) and the first test stores '<think>\nWeighing it'.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/chat_db_teardown.dart';

/// Streams [pieces] slowly; once [abort] is set the next read throws the
/// error the http package raises when the client is closed mid-stream.
class _AbortingFeed extends LLMService {
  List<String> pieces = ['She waves.'];
  bool abort = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt == null) {
      yield '';
      return;
    }
    for (final p in List.of(pieces)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (abort) {
        throw http.ClientException(
          'Connection closed before full header was received',
        );
      }
      yield p;
    }
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'AbortingFeed';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_abortthink_').path;
        }
        return null;
      });

  late _AbortingFeed llm;
  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    llm = _AbortingFeed();
    db = AppDatabase.forTesting();
    final storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.backendSettings.setReasoningEnabled(true);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the client-abort think test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-abort-think',
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'timed out waiting for $what');
  }

  Future<void> settled() =>
      until(() => !chat.isGenerating && !chat.isSettlingTurn, 'turn to end');

  Future<void> stopByAbort() async {
    llm.abort = true;
    chat.stopGeneration();
  }

  test('a client abort inside a thought stores the closer', () async {
    llm.pieces = [
      '<think>\nWeighing it ',
      'over ',
      for (var i = 0; i < 60; i++) 'slowly ',
    ];
    final send = chat.sendMessage('Evening.');
    await until(
      () =>
          !chat.messages.last.isUser &&
          chat.messages.last.text.contains('Weighing'),
      'the thought to stream',
    );
    await stopByAbort();
    await send;
    await settled();

    final text = chat.messages.last.text;
    expect(text, contains('Weighing'));
    expect(
      text.trimRight(),
      endsWith('</think>'),
      reason: 'the catch path must salvage the thought like the clean Stop',
    );
    expect(splitMessageForEdit(text).body.trim(), isEmpty);
  });

  test('a client abort in plain prose keeps the partial, no banner', () async {
    llm.pieces = ['She waves ', for (var i = 0; i < 60; i++) 'slowly '];
    final send = chat.sendMessage('Evening.');
    await until(
      () =>
          !chat.messages.last.isUser &&
          chat.messages.last.text.contains('She waves'),
      'the reply to stream',
    );
    final before = chat.messages.length;
    await stopByAbort();
    await send;
    await settled();

    expect(chat.messages.length, before);
    expect(chat.messages.last.text, startsWith('She waves'));
    expect(chat.messages.last.text, isNot(contains('</think>')));
  });
}
