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

// #339: Generate reply on a trailing user message (reply deleted, cancelled,
// failed, or a fork at the user line) produced a reply with no Realism pass.
// The turn's score rode the lost reply, so the user line must be rewound to
// its pre-turn stamp and scored again — same deltas as the first time, never
// missing and never stacked.
//
// Full turns run against the E2E FakeBackendServer through a real
// OpenRouterService, like regen_chip_attach_test. Its relationship judge pays
// a fixed bond delta, so a missed score and a double score both show up.

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

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
      'realism_default': true,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['The fake backend replies ', 'about the porch.'],
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
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Rescore Tester',
        description: 'Exists only inside the generate-reply rescore test.',
        firstMessage: 'Welcome to the rescore porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-rescore',
    );
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  int bond() => chat.relationshipService.affectionScore;

  test(
    'delete reply → Generate reply re-scores once, not zero or twice',
    () async {
      final before = bond();
      await chat.sendMessage('I bring you a cup of tea.');
      final scored = bond();
      expect(scored, isNot(before), reason: 'baseline: the send must score');

      chat.deleteMessage(chat.messages.length - 1);
      await _drain();
      expect(chat.messages.last.isUser, isTrue);

      await chat.regenerateLastMessage();
      await _drain();

      expect(chat.messages.last.isUser, isFalse);
      expect(
        bond(),
        scored,
        reason:
            'same user line, same baseline → same bond; a higher value '
            'means the deleted turn\'s score was stacked',
      );
      expect(
        chat.messages.last.activeMetadata?['realism_state'],
        isA<Map>(),
        reason: 'the new reply carries the turn\'s realism stamp',
      );
    },
  );

  test('fork at a user line → Generate reply scores that line', () async {
    await chat.sendMessage('I bring you a cup of tea.');
    final afterFirst = bond();
    await chat.sendMessage('I sit beside you and smile.');
    final afterSecond = bond();
    expect(afterSecond, isNot(afterFirst), reason: 'baseline: turn 2 scores');

    final userIdx = chat.messages.lastIndexWhere((m) => m.isUser);
    await chat.forkFromMessage(userIdx);
    await _drain();
    expect(chat.messages.last.isUser, isTrue);
    expect(bond(), afterFirst, reason: 'fork rewinds to before turn 2');

    await chat.regenerateLastMessage();
    await _drain();

    expect(
      bond(),
      afterSecond,
      reason: 'the forked user line must be scored exactly like the original',
    );
  });
}
