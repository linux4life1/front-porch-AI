// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// With-you is a post-gen write like posture. The snapshot on the reply is
// overwritten with the glance the reply ended in, so regen must restore
// the turn START from kWithUserPreTurn (audit P1.7). Swipe already reads
// the restamped POST on realism_state; Continue keeps the first receipt
// via putIfAbsent.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_withuser_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She stays on the porch with you.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture": "none"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
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

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 300 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('regen restores the pre-reply glance, not the restamped post', () async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the with-user rewind test.',
      firstMessage: 'The porch light hums.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-withuser-1';
    await chat.setActiveCharacter(card);
    chat.relationshipService.setWithUser(false);

    await chat.sendMessage('Evening.');
    await drainTurn();

    final first = chat.messages.lastWhere((m) => !m.isUser);
    expect(
      first.activeMetadata!.containsKey(kWithUserPreTurn),
      isTrue,
      reason: 'restamp must park the turn-start glance beside the snapshot',
    );
    expect(first.activeMetadata![kWithUserPreTurn], isFalse);
    expect(
      (first.activeMetadata!['realism_state'] as Map)['withUser'],
      isTrue,
      reason: 'the glance pass wrote true; that is POST, not the rewind base',
    );

    await chat.regenerateLastMessage();
    await drainTurn();

    final second = chat.messages.lastWhere((m) => !m.isUser);
    expect(
      second.activeMetadata![kWithUserPreTurn],
      isFalse,
      reason:
          'regen must capture from the restored START (false). If this is '
          'true, the leftover POST leaked into the next turn.',
    );
  });
}
