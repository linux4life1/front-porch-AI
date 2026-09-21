// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Switching models mid-chat (and the regen people do right after) must not
// wipe the Journal recap or Growth Rings. Recap clear is for rewrites INSIDE
// the already-journaled window — not for a new model's first regen of the
// unjournaled tip.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_model_switch_mem_')
              .path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She nods on the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentLlm';
}

Future<void> _awaitQuiet(ChatService chat) async {
  for (var i = 0; i < 200 && (chat.isGenerating || chat.isSettlingTurn); i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
      'realism_default': false,
      'journal_enabled': true,
      'character_evolution_enabled': true,
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
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<CharacterCard> openChat() async {
    final card = CharacterCard(
      name: 'Mara',
      description: 'Exists only for the model-switch memory test.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-model-switch-1';
    await chat.setActiveCharacter(card);
    return card;
  }

  test(
    'regen of an unjournaled last reply keeps the recap and planted rings',
    () async {
      final card = await openChat();
      await chat.sendMessage('Tell me about the evening.');
      await _awaitQuiet(chat);
      expect(chat.messages.last.isUser, isFalse);

      const recap = 'We are on the porch. The storm has passed.';
      chat.setSummary(recap);
      await chat.plantGrowthRingFor(
        card.stableGroupId,
        'Has started trusting the quiet between us.',
      );
      expect(chat.summary, recap);
      expect(chat.growthRingsForOwner(card.stableGroupId), isNotEmpty);

      await chat.regenerateLastMessage();
      await _awaitQuiet(chat);

      expect(
        chat.summary,
        recap,
        reason:
            'the last reply is past the journal cursor, so the recap does '
            'not describe it — regen must not blank "Where we are"',
      );
      expect(
        chat.growthRingsForOwner(card.stableGroupId).map((r) => r.content),
        contains('Has started trusting the quiet between us.'),
        reason: 'a planted ring with no receipts is not discarded-plot',
      );
    },
  );

  test('rewrite inside the journaled window still clears the recap', () async {
    await openChat();
    await chat.sendMessage('Stay a while.');
    await _awaitQuiet(chat);
    final sid = chat.currentSessionId!;
    const recap = 'We never left the living room.';
    await db.patchSession(
      SessionsCompanion(
        id: Value(sid),
        summary: const Value(recap),
        summaryLastIndex: Value(chat.messages.length),
      ),
    );
    await chat.reloadCurrentSession();
    expect(chat.summary, recap);
    expect(chat.summaryLastIndex, chat.messages.length);

    await chat.regenerateLastMessage();
    await _awaitQuiet(chat);

    expect(
      chat.summary,
      isEmpty,
      reason:
          'the recap already covered this position — rewriting it would '
          're-inject discarded plot as "earlier in this story"',
    );
  });

  test(
    'changing the loaded model path does not wipe recap or growth rings',
    () async {
      final card = await openChat();
      const recap = 'We are in the kitchen. The kettle just clicked off.';
      chat.setSummary(recap);
      await chat.plantGrowthRingFor(
        card.stableGroupId,
        'Keeps the porch light on until I get home.',
      );
      expect(chat.growthRingsForOwner(card.stableGroupId), isNotEmpty);

      await storage.backendSettings.setLastUsedModelPath(
        '/tmp/other-model.gguf',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        chat.summary,
        recap,
        reason: 'a model switch is not a timeline rewrite',
      );
      expect(
        chat.growthRingsForOwner(card.stableGroupId).map((r) => r.content),
        contains('Keeps the porch light on until I get home.'),
        reason: 'growth cache must still serve the open chat after a retest',
      );
    },
  );
}
