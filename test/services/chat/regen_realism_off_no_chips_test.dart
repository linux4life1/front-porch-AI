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

// A regen with the Realism Engine off must not carry realism chips.
// Reported 2026-09-30: regen showed Bond unchanged / Mood / Trust unchanged
// with Realism off because the regen path stamped the stale mood.

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
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['A plain reply ', 'with Realism off.'],
    );
    final llm = OpenRouterService(
      apiUrl: '${backend.baseUrl}/v1',
      modelName: 'smoke-model',
    );
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
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Realism Off Tester',
        description: 'Exists only inside the realism-off regen test.',
        firstMessage: 'Welcome to the quiet porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-regen-off',
    );
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  test(
    'a regen with Realism off stamps no mood, so no realism chips show',
    () async {
      await chat.sendMessage('I sit on the steps.');
      final original = chat.messages.last;
      expect(original.isUser, isFalse);
      expect(
        original.activeMetadata?['emotion_label'],
        isNull,
        reason: 'baseline: a fresh Realism-off turn has no mood',
      );

      await chat.regenerateLastMessage();
      final regenerated = chat.messages.last;
      expect(regenerated.swipes.length, 2);
      final meta = regenerated.activeMetadata ?? const <String, dynamic>{};
      expect(
        meta['emotion_label'],
        isNull,
        reason:
            'Realism off: a regen must not stamp a mood. One mood key lights '
            'the Mood chip and the Bond/Trust unchanged chips '
            '(keys: ${meta.keys.toList()})',
      );
      expect(meta.containsKey('bond_delta'), isFalse);
      expect(meta.containsKey('trust_delta'), isFalse);
      expect(chat.isGenerating, isFalse);
    },
  );
}
