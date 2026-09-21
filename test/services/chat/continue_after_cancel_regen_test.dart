// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Cancel a regenerate, then Continue. Continue must not stamp the cancelled
// eval's pending realism_state / chips onto the restored bubble.

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
          return Directory.systemTemp.createTempSync('fpai_contcancel_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  Future<void> Function()? cancel;
  bool cancelNextEval = false;
  int chatCalls = 0;
  bool _aborted = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatCalls++;
      yield '*She leans in, warmer than before.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      if (cancelNextEval) {
        cancelNextEval = false;
        _aborted = true;
        await cancel?.call();
        return;
      }
      if (_aborted) return;
      yield '{"relationship_delta":8,"trust_delta":0,'
          '"bond_reason":"warm","trust_reason":"steady"}';
      return;
    }
    if (_aborted) return;
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"happy","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
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
    llm.cancel = () => chat.cancelRealismEval();
    await storage.initialized;
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
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'cancel regen then Continue does not stamp cancelled realism_state',
    () async {
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the continue-after-cancel test.',
        firstMessage: 'The screen door bangs shut behind you.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-contcancel-1';
      await chat.setActiveCharacter(card);

      await chat.sendMessage('I missed you.');
      await drainTurn();

      final accepted = Map<String, dynamic>.from(
        chat.messages.last.activeMetadata ?? const {},
      );
      final acceptedText = chat.messages.last.text;
      final acceptedBond = chat.relationshipService.affectionScore;

      llm.cancelNextEval = true;
      await chat.regenerateLastMessage();
      await drainTurn();

      expect(chat.messages.last.text, acceptedText);
      expect(chat.relationshipService.affectionScore, acceptedBond);

      await chat.continueGeneration();
      await drainTurn();

      final after = chat.messages.last.activeMetadata ?? const {};
      expect(
        after['realism_state'],
        accepted['realism_state'],
        reason:
            'Continue must not inherit a cancelled regen\'s pending snapshot',
      );
      expect(after['needs_deltas'], accepted['needs_deltas']);
      expect(chat.relationshipService.affectionScore, acceptedBond);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
