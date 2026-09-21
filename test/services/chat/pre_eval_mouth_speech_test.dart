// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live poke on chore/dead-code-and-fake-tests: one-shot finished, PRE-GEN
// attach logged, then the reply card stayed empty (Qwen parked the line in
// <think>, displayText stripped it, no empty-speech banner). This send
// goes red if that mouth is skipped or left invisible after a successful
// pre-eval.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_pre_eval_mouth_')
              .path;
        }
        return null;
      });
}

const _kOneShotJson =
    '{"relationship_delta":-1,"trust_delta":-2,'
    '"bond_reason":"deflated","trust_reason":"wary",'
    '"emotion":"deflated","emotion_intensity":"mild",'
    '"fixation_topic":"none","proposed_objective":"none"}';

const _kThinkOnlyMouth = '<think>She looks down the porch steps.</think>';

class _ThinkOnlyMouthLlm extends LLMService {
  int mouthStarts = 0;
  int oneShotStarts = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      mouthStarts++;
      yield _kThinkOnlyMouth;
      return;
    }
    oneShotStarts++;
    yield _kOneShotJson;
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ThinkOnlyMouthLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ThinkOnlyMouthLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ThinkOnlyMouthLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.realismSettings.setOneShotMode(OneShotMode.on);
    await storage.realismSettings.setPassageOfTimeDefault(false);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('closed think-only lifts; unclosed think is salvaged not lifted', () {
    expect(
      resolveMouthSpeech(_kThinkOnlyMouth),
      'She looks down the porch steps.',
    );
    const cutOff =
        '<think>\nWondering how to phrase this, but the connection drops here...';
    final salvaged = resolveMouthSpeech(cutOff);
    expect(salvaged.trim(), endsWith('</think>'));
    expect(salvaged, contains('connection drops here'));
    expect(
      ChatMessage(
        text: salvaged,
        sender: 'Jennifer',
        isUser: false,
      ).displayText,
      isEmpty,
    );
  });

  test(
    'successful one-shot pre-eval is followed by visible mouth speech',
    () async {
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Flora',
          description: 'Exists only inside the pre-eval mouth pin.',
          firstMessage: 'The porch light is on.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        )..dbId = 'char-pre-eval-mouth',
      );

      await chat.sendMessage('Hey.');
      await drainTurn();

      expect(
        llm.oneShotStarts,
        greaterThan(0),
        reason: 'one-shot must actually fire before the mouth',
      );
      expect(
        llm.mouthStarts,
        greaterThan(0),
        reason: 'PRE-GEN attach without generateStream is a skipped mouth',
      );

      final reply = chat.messages.last;
      expect(reply.isUser, isFalse);
      expect(reply.sender, 'Flora');
      expect(
        reply.activeMetadata?['bond_delta'],
        -1,
        reason:
            'chips from the successful pre-eval must still be on the bubble',
      );
      expect(reply.displayText.trim(), isNotEmpty);
      expect(reply.displayText, contains('porch steps'));
      expect(reply.text, isNot(kEmptySpeechAfterPregenNotice));
    },
  );
}
