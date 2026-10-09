// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Thinking 1797s..." sat on the character's last reply while Impersonate
// wrote the user's line. Two things fed it, both pinned here on the real
// ChatService:
//  - a reply that thought kept its live think start after the stream ended,
//    and a regenerate that did not think showed it again on the new swipe;
//  - Impersonate ran with the reply phase still "idle", so nothing could
//    tell a bubble (or the status strip) that no bubble was being written.

import 'dart:async';
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
          return Directory.systemTemp.createTempSync('fpai_imp_timer_').path;
        }
        return null;
      });
}

Future<({AppDatabase db, ChatService chat, FakeBackendServer backend})>
_buildChat({Duration chatChunkDelay = Duration.zero}) async {
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': false,
    // The first reply thinks; the regenerate below does not.
    'reasoning_enabled': true,
  });
  final backend = await FakeBackendServer.start(
    replyPieces: [
      '<think>she weighs the porch light',
      '</think>',
      ' Hello.',
      ' I sit down.',
    ],
    chatChunkDelay: chatChunkDelay,
  );
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
        ..testLlmServiceOverride = OpenRouterService(
          apiUrl: '${backend.baseUrl}/v1',
          modelName: 'smoke-model',
        );
  await storage.initialized;
  await chat.setActiveCharacter(
    CharacterCard(
      name: 'Mara',
      description: 'A porch regular.',
      firstMessage: 'The porch light hums.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-imp-timer',
  );
  return (db: db, chat: chat, backend: backend);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  setUp(() => HttpOverrides.global = null);

  test(
    'a regenerate that does not think leaves no live think start behind',
    () async {
      final h = await _buildChat();
      addTearDown(() async {
        h.chat.dispose();
        await h.backend.close();
        await h.db.close();
      });

      await h.chat.sendMessage('Evening.');
      final first = h.chat.messages.last;
      expect(first.isUser, isFalse);
      expect(first.thinkingDurationMs, greaterThan(0));

      h.backend.replyPieces
        ..clear()
        ..add(' Hello again.');
      await h.chat.regenerateLastMessage();

      final last = h.chat.messages.last;
      expect(last.swipes.length, 2);
      // The swipe now showing never thought ...
      expect(last.thinkingDurationMs, 0);
      // ... so a start left from the first swipe would read as a think
      // still running, timed from then, whenever the app is busy.
      expect(last.thinkingStartTime, isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Impersonate runs under its own phase and leaves the bubbles alone',
    () async {
      final h = await _buildChat(
        chatChunkDelay: const Duration(milliseconds: 150),
      );
      addTearDown(() async {
        h.chat.dispose();
        await h.backend.close();
        await h.db.close();
      });

      await h.chat.sendMessage('Evening.');
      final lastBefore = h.chat.messages.last;
      final countBefore = h.chat.messages.length;

      // The impersonate stream thinks too; none of it may reach a bubble.
      final firstToken = Completer<void>();
      var seen = '';
      final run = h.chat.impersonateUser(
        onToken: (acc) {
          seen = acc;
          if (!firstToken.isCompleted) firstToken.complete();
        },
      );
      await firstToken.future.timeout(const Duration(seconds: 60));

      expect(h.chat.isGenerating, isTrue);
      expect(h.chat.generationPhase, GenerationPhase.impersonating);
      expect(lastBefore.thinkingStartTime, isNull);

      await run;
      expect(h.chat.isGenerating, isFalse);
      expect(h.chat.generationPhase, GenerationPhase.idle);
      expect(h.chat.messages.length, countBefore);
      expect(identical(h.chat.messages.last, lastBefore), isTrue);
      expect(seen, isNot(contains('weighs')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
