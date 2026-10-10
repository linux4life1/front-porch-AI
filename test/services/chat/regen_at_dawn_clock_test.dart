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

// A regenerated reply that said "They're serving cinnamon rolls at dawn now"
// took the story clock from 9:00 AM back to 6:00 AM, while the reply's chip
// said "same moment". "at dawn" is a schedule, the same as "at 6 a.m.", which
// the reply-named clock already refuses. "It's dawn" and "in the dawn" still
// set the clock.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show clockNamedInReply;
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

const _swipeOne =
    '*Adjusts her floral apron.* Oh, you know, the usual. Pruned my rose '
    'bushes. What have you been up to?';

// The swipe-2 reply from the live run, thought included (Request thinking
// was on): the thought names 9 AM, the visible text says "at dawn".
const _swipeTwo = <String>[
  '<think>First, the time is 9 AM on a Saturday. She is on the porch '
      'swing.</think>',
  '*Adjusts her floral shawl, eyes crinkling as she smiles.* Oh, it was '
      '*just* fine, thank you. ',
  'Say, did you hear about the new bakery opening downtown? They’re '
      'serving cinnamon rolls at dawn now. Rumor has it they’re '
      '*dangerous*.',
];

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_dawn_regen_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('clockNamedInReply: "at dawn" is a schedule', () {
    final nine = DateTime.utc(2026, 10, 10, 9, 0);

    test('a bakery that serves rolls at dawn does not name the hour', () {
      expect(
        clockNamedInReply('They’re serving cinnamon rolls at dawn now.', nine),
        isNull,
      );
      expect(clockNamedInReply('We ride at dawn.', nine), isNull);
    });

    test('"it\'s dawn" and "in the dawn" still set 6:00', () {
      final six = DateTime.utc(2026, 10, 10, 6, 0);
      expect(clockNamedInReply("It's dawn on the porch.", nine), six);
      expect(
        clockNamedInReply('It is dawn and the street is grey.', nine),
        six,
      );
      expect(
        clockNamedInReply('*The river moves slow in the dawn.*', nine),
        six,
      );
    });
  });

  group('regenerate with a reply that says "at dawn"', () {
    AppDatabase? db;
    StorageService? storage;
    CharacterRepository? repo;
    ChatService? chat;
    FakeBackendServer? backend;

    setUp(() {
      db = null;
      storage = null;
      repo = null;
      chat = null;
      backend = null;
    });

    Future<void> drain() async {
      for (
        var i = 0;
        i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    tearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend?.close();
    });

    test('the clock does not go back to 6:00 AM', () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
        'needs_sim_default': false,
        'passage_of_time_default': true,
      });
      db = AppDatabase.forTesting();
      backend = await FakeBackendServer.start(replyPieces: [_swipeOne]);
      storage = StorageService();
      repo = CharacterRepository(db!, storage!);
      chat =
          ChatService(
              KoboldService(storage!),
              UserPersonaService(db!),
              storage!,
              WorldRepository(storage!, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo!)
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend!.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      await storage!.initialized;
      await storage!.realismSettings.setOneShotMode(OneShotMode.off);
      final card = CharacterCard(
        name: 'Carmen',
        firstMessage: '*Carmen waves from her porch swing.* Evening, neighbor.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
          passageOfTimeEnabled: true,
        ),
      );
      await repo!.addCharacter(card);
      await chat!.setActiveCharacter(card);
      await chat!.setPassageOfTimeEnabled(true);
      await drain();

      final start = chat!.timeService.clock;
      final nine = DateTime.utc(start.year, start.month, start.day, 9, 0);
      await chat!.timeService.setClockDirect(nine);

      await chat!.sendMessage('Evening, Carmen. How was your day?');
      await drain();
      final afterSwipeOne = chat!.timeService.clock;
      expect(
        afterSwipeOne.isAfter(nine),
        isTrue,
        reason:
            'the first reply must tick the clock, or the test proves '
            'nothing',
      );

      backend!.replyPieces
        ..clear()
        ..addAll(_swipeTwo);
      await chat!.regenerateLastMessage();
      await drain();

      final reply = chat!.messages.last;
      expect(reply.text, contains('at dawn'));
      expect(reply.swipeIndex, 1);
      final clock = chat!.timeService.clock;
      expect(
        clock.isBefore(nine),
        isFalse,
        reason:
            'a reply about what a bakery serves at dawn moved the story '
            'clock from 9:00 AM back to $clock',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
