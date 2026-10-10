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

// Phone twin of test/ui/chat_components/clock_only_reply_no_realism_chips_test
// .dart. Passage of Time runs with the Realism engine off, so a reply in such
// a chat carries a time chip and nothing else. The phone's chip feed counted
// that time chip as a scored reply and sent "Bond unchanged · Trust
// unchanged" under every reply. A real zero from the judge still says
// "unchanged", and an unreadable judge sends the desktop's own chip text.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kFeelingsUnscoredLabel, kFeelingsUnscoredTip;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clock_chip_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  FakeBackendServer? backend;

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

  Future<void> boot({required bool realism}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': realism,
      'needs_sim_default': false,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['She leans on the porch rail ', 'and smiles.'],
    );
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
      name: 'Clock Tester',
      firstMessage: 'Welcome to the porch.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: realism,
        needsSimEnabled: false,
        chaosModeEnabled: false,
        passageOfTimeEnabled: true,
      ),
    );
    await repo!.addCharacter(card);
    await chat!.setActiveCharacter(card);
    await chat!.setRealismEnabled(realism);
    await chat!.setPassageOfTimeEnabled(true);
    await drain();
  }

  Map<String, dynamic> phoneChips() {
    final facade = ChatFacade(chat!, repo!, null, null, null);
    final msgs = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    return Map<String, dynamic>.from((msgs.last['chips'] as Map?) ?? const {});
  }

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    await backend?.close();
  });

  test('Realism off, clock on: the reply has a time chip and no bond or '
      'trust chip', () async {
    await boot(realism: false);
    await chat!.sendMessage('Just talking while the porch clock ticks.');
    await drain();

    final meta = chat!.messages.last.activeMetadata ?? const {};
    expect(
      (meta['time_passed'] as String?)?.isNotEmpty,
      isTrue,
      reason: 'the clock must stamp this reply, or the test proves nothing',
    );
    expect(meta.containsKey('bond_delta'), isFalse);
    expect(meta.containsKey('emotion_label'), isFalse);

    final chips = phoneChips();
    expect(chips['timePassed'], meta['time_passed']);
    expect(
      chips.containsKey('bondDelta'),
      isFalse,
      reason: 'a time chip alone is not a scored reply',
    );
    expect(chips.containsKey('trustDelta'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Realism on, the judge answers 0 and 0: the phone still says '
      'unchanged', () async {
    await boot(realism: true);
    backend!.feelingsJudgeAnswer =
        '{"relationship_delta":0,"trust_delta":0,'
        '"bond_reason":"steady","trust_reason":"steady"}';
    await chat!.sendMessage('I bring you a cup of tea.');
    await drain();
    expect(backend!.feelingsJudgeAnswersServed, greaterThan(0));

    final chips = phoneChips();
    expect(chips['bondDelta'], 0);
    expect(chips['trustDelta'], 0);
    expect(chips['feelingsUnscored'], isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an unreadable judge: the phone gets the desktop chip text', () async {
    await boot(realism: true);
    backend!.feelingsJudgeAnswer = '';
    await chat!.sendMessage('I bring you a cup of tea.');
    await drain();

    final chips = phoneChips();
    expect(chips['feelingsUnscored'], isTrue);
    expect(chips['feelingsUnscoredLabel'], kFeelingsUnscoredLabel);
    expect(chips['feelingsUnscoredTip'], kFeelingsUnscoredTip);
    expect(chips.containsKey('bondDelta'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
