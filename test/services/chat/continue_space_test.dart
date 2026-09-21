// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Continue word-break (Discord 2026-08-15, adv997): the last word and the
// next word mashed ("steps.Then") because Continue concatenated raw tokens
// and models often emit no leading space. Users edited a trailing space
// into the bubble before hitting Continue.
//
// New file on purpose — test-integrity blocks edits to existing tests.
// Guards proven red before green: restore `'$prefix$newPart'.trimRight()`
// in postgen and drop padContinuePartial → mash test fails with steps.Then
// and the suffix assert fails.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_cont_space_').path;
        }
        return null;
      });
}

Future<({AppDatabase db, ChatService chat, StorageService storage})> _buildChat(
  OpenRouterService llm,
) async {
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': false,
  });
  final db = AppDatabase.forTesting();
  final storage = StorageService();
  final chat =
      ChatService(
          KoboldService(storage),
          UserPersonaService(db),
          storage,
          WorldRepository(storage, db),
        )
        ..setDatabase(db)
        ..testLlmServiceOverride = llm;
  await storage.initialized;
  await chat.setActiveCharacter(
    CharacterCard(
      name: 'Mara',
      description: 'Exists only inside the continue-space test.',
      firstMessage: 'The porch light hums.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-continue-space',
  );
  return (db: db, chat: chat, storage: storage);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'Continue inserts a word-break space so the next word does not mash',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: ['She waved from the steps.'],
      );
      final llm = OpenRouterService(
        apiUrl: '${backend.baseUrl}/v1',
        modelName: 'smoke-model',
      );
      final h = await _buildChat(llm);
      addTearDown(() async {
        h.chat.dispose();
        await backend.close();
        await h.db.close();
      });

      await h.chat.sendMessage('Hi.');
      expect(h.chat.messages.last.text, 'She waved from the steps.');

      // No leading space on the continuation — the Discord mash case.
      backend.replyPieces
        ..clear()
        ..add('Then she sat on the rail.');
      await h.chat.continueGeneration();
      for (var i = 0; i < 50 && h.chat.isSettlingTurn; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final after = h.chat.messages.last.text;
      expect(
        after,
        'She waved from the steps. Then she sat on the rail.',
        reason:
            'Continue must insert a word-break space when the model emits '
            'none (Discord 2026-08-15). Old concat produced steps.Then.',
      );
      expect(after, isNot(contains('steps.Then')));

      final lastUser =
          (jsonDecode(backend.lastChatBody) as Map)['messages'].last['content']
              as String;
      expect(
        lastUser.contains('She waved from the steps. '),
        isTrue,
        reason:
            'Continue suffix must be padded so the model sees a word break '
            '(the edit-a-space-in workaround)',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('Continue does not double a space the model already emitted', () async {
    HttpOverrides.global = null;
    final backend = await FakeBackendServer.start(
      replyPieces: ['She waved from the steps.'],
    );
    final llm = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );
    final h = await _buildChat(llm);
    addTearDown(() async {
      h.chat.dispose();
      await backend.close();
      await h.db.close();
    });

    await h.chat.sendMessage('Hi.');
    backend.replyPieces
      ..clear()
      ..add(' Then she sat.');
    await h.chat.continueGeneration();
    for (var i = 0; i < 50 && h.chat.isSettlingTurn; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(
      h.chat.messages.last.text,
      'She waved from the steps. Then she sat.',
      reason: 'a model-emitted leading space must not become a double',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));
}
