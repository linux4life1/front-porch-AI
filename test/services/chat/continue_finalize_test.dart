// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Continue P0 package (full-codebase audit 2026-08-11):
//   1) Finalize merges pre-continue body + new tokens (sanitizer must not
//      collapse the bubble to the continuation fragment alone).
//   2) Continue suffix uses think-stripped promptText, not raw .text.
//   3) Continue plan clears porch_night (force-ack opening) with state zone.
//
// Guards proven red before green: drop continuePrefix re-merge → first fails;
// use raw .text in suffix → second fails; skip porch_night clear → third fails.

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
          return Directory.systemTemp.createTempSync('fpai_continue_').path;
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
  // First send must keep `<think>` on .text so Continue can prove it
  // uses promptText, not raw think (f2cf39e7 peels think when wrap is off).
  await storage.backendSettings.setReasoningEnabled(true);
  await chat.setActiveCharacter(
    CharacterCard(
      name: 'Mara',
      description: 'Exists only inside the continue-finalize test.',
      firstMessage: 'The porch light hums.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-continue-p0',
  );
  return (db: db, chat: chat, storage: storage);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'Continue + sanitizer keeps the pre-continue body in the saved bubble',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: [
          'She set her mug on the rail and looked at the garden. ',
          'The evening air was warm.',
        ],
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

      await h.storage.generationSettings.setOutputSanitizerEnabled(true);
      await h.storage.generationSettings.setOutputSanitizerRules(const [
        OutputSanitizerRule(id: 1, find: 'FRAGMENT', replace: 'quiet'),
      ]);

      await h.chat.sendMessage('Tell me about the evening.');
      final preBody = h.chat.messages.last.text;
      expect(preBody, contains('mug on the rail'));
      expect(preBody, contains('evening air was warm'));

      // Continue: only a fragment; sanitizer rewrites FRAGMENT → quiet.
      // ASCII only — FakeBackend SSE encoding rejects some unicode.
      backend.replyPieces
        ..clear()
        ..add(' And then - FRAGMENT night.');
      await h.chat.continueGeneration();
      // Drain settling (postgen sanitize + save).
      for (var i = 0; i < 50 && h.chat.isSettlingTurn; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final after = h.chat.messages.last;
      expect(after.isUser, isFalse);
      expect(
        after.text,
        contains('mug on the rail'),
        reason:
            'pre-continue body must survive finalize (P0.1) - without the '
            'prefix re-merge, only the continuation fragment is saved',
      );
      expect(after.text, contains('evening air was warm'));
      expect(
        after.text,
        contains('quiet night'),
        reason: 'sanitizer still runs on the full merged body',
      );
      expect(after.text, isNot(contains('FRAGMENT')));
      expect(
        after.text.length,
        greaterThan(preBody.length),
        reason: 'continuation tokens must append, not replace',
      );
      expect(h.chat.isGenerating, isFalse);
      expect(h.chat.isSettlingTurn, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'Continue suffix is think-stripped (does not re-feed closed plans)',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: [
          '<think>\nPrior plan: open with the massage scene again.\n</think>\n',
          'She waved from the steps.',
        ],
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
      expect(h.chat.messages.last.text, contains('<think>'));
      expect(h.chat.messages.last.promptText, isNot(contains('<think>')));

      backend.replyPieces
        ..clear()
        ..add(' Softly.');
      await h.chat.continueGeneration();

      final lastUser =
          (jsonDecode(backend.lastChatBody) as Map)['messages'].last['content']
              as String;
      expect(
        lastUser,
        isNot(contains('Prior plan: open with the massage scene')),
        reason:
            'Continue suffix must use promptText (P0.2) — raw .text re-injects '
            'closed think blocks into the generation prompt',
      );
      expect(lastUser, contains('She waved from the steps.'));
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'Continue plan clears porch_night with the rest of the state strip',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: ['She sat on the porch swing.'],
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

      await h.chat.sendMessage('Evening.');

      // Arm force-ack so the next plan would inject REQUIRED OPENING unless
      // Continue strips porch_night.
      final diaryId = h.chat.characterIdFor(h.chat.activeCharacter!);
      h.chat.debugArmPorchNightForTest(
        diaryCharacterId: diaryId,
        injectionText:
            '\n[TABLE TALK — HARD REQUIRED OPENING: the FIRST 2–4 sentences '
            'MUST be clear table talk about Mafia.]\n',
      );

      backend.replyPieces
        ..clear()
        ..add(' And hummed.');
      await h.chat.continueGeneration();

      final contUser =
          (jsonDecode(backend.lastChatBody) as Map)['messages'].last['content']
              as String;
      expect(
        contUser.toLowerCase(),
        isNot(contains('required opening')),
        reason: 'Continue must clear porch_night (P0.3)',
      );
      expect(
        contUser.toLowerCase(),
        isNot(contains('hard required')),
        reason: 'force-ack table-talk must not ride a pure append',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
