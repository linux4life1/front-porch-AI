// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Thought for Ns" per swipe, on the real ChatService against a real
// listening backend:
//  - a regenerate merged its new swipe with a thinking time of 0, so the
//    time measured while it streamed was lost and the swipe never said how
//    long it thought;
//  - a stream that broke mid-think left its live start on the message.

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
          return Directory.systemTemp.createTempSync('fpai_regen_think_').path;
        }
        return null;
      });
}

Future<({AppDatabase db, ChatService chat, FakeBackendServer backend})>
_buildChat(List<String> replyPieces) async {
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': false,
    // Without it the app strips <think> and nothing is timed.
    'reasoning_enabled': true,
  });
  final backend = await FakeBackendServer.start(
    replyPieces: replyPieces,
    // Each piece arrives this long after the last, so a think's length is
    // set by how many pieces sit inside it.
    chatChunkDelay: const Duration(milliseconds: 120),
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
    )..dbId = 'char-regen-think',
  );
  return (db: db, chat: chat, backend: backend);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  setUp(() => HttpOverrides.global = null);

  test(
    'a regenerated swipe keeps its own thinking time, and swiping shows each',
    () async {
      // One piece inside the think: about one chunk delay of thinking.
      final h = await _buildChat([
        '<think>she weighs the porch light',
        '</think>',
        ' Hello.',
      ]);
      addTearDown(() async {
        h.chat.dispose();
        await h.backend.close();
        await h.db.close();
      });

      await h.chat.sendMessage('Evening.');
      final firstMs = h.chat.messages.last.thinkingDurationMs;
      expect(firstMs, greaterThan(0));

      // Five pieces inside the think: clearly longer than the first.
      h.backend.replyPieces
        ..clear()
        ..addAll([
          '<think>she looks',
          ' at the road',
          ' and the fence',
          ' and the sky',
          ' and back',
          '</think>',
          ' Hello again.',
        ]);
      await h.chat.regenerateLastMessage();

      final msg = h.chat.messages.last;
      final idx = h.chat.messages.length - 1;
      expect(msg.swipes.length, 2);
      expect(msg.swipeIndex, 1);
      final secondMs = msg.thinkingDurationMs;
      expect(
        secondMs,
        greaterThan(firstMs),
        reason: 'the new swipe shows the time it actually thought',
      );
      expect(msg.thinkingStartTime, isNull);

      await h.chat.swipeMessage(idx, -1);
      expect(h.chat.messages.last.swipeIndex, 0);
      expect(h.chat.messages.last.thinkingDurationMs, firstMs);

      await h.chat.swipeMessage(idx, 1);
      expect(h.chat.messages.last.swipeIndex, 1);
      expect(h.chat.messages.last.thinkingDurationMs, secondMs);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a stream that breaks mid-think leaves no live think start behind',
    () async {
      // The think never closes before the backend goes away.
      final h = await _buildChat([
        '<think>she weighs',
        ' the porch light',
        ' and the road',
        ' and the sky',
        ' and the fence',
        '</think>',
        ' Hello.',
      ]);
      addTearDown(() async {
        h.chat.dispose();
        await h.db.close();
      });

      final send = h.chat.sendMessage('Evening.');
      ChatMessage? target;
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (target == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        for (final m in h.chat.messages) {
          if (m.thinkingStartTime != null) target = m;
        }
      }
      expect(target, isNotNull, reason: 'the reply started thinking');

      // Drop the connection mid-stream: the read throws inside the turn.
      await h.backend.close();
      await send;

      expect(h.chat.isGenerating, isFalse);
      expect(target!.thinkingStartTime, isNull);
      expect(target.thinkingDurationMs, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
