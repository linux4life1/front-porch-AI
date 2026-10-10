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

// A group turn stopped before its reply exists did not take a turn. Ada is
// up, the user stops her reply during the Realism check, and Try again
// answers as Ada; the next send goes to Bex. The pick used to advance the
// rotation at the start of the turn, so Try again went to Bex and Bex
// answered twice in a row.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
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

const _on = '{"realism_engine":{"realism_enabled":true}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'journal_enabled': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['The porch boards creak.'],
    );
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
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-try', name: 'Duet'));
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bex', 'Bex')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-try',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(_on),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-try', name: 'Duet'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  /// Press "Stop this reply" the moment the next Realism check opens, the
  /// way the overlay's button does (it calls the same method).
  void stopDuringNextRealismCheck() {
    var pressed = false;
    void listener() {
      if (pressed || !chat.isEvaluatingRealism) return;
      pressed = true;
      chat.removeListener(listener);
      chat.cancelRealismEval();
    }

    chat.addListener(listener);
  }

  List<String> speakers() => [
    for (final m in chat.messages)
      if (!m.isUser && m.sender != 'System') m.sender,
  ];

  test(
    'Ada stopped, Try again answers as Ada, the next send goes to Bex',
    () async {
      expect(chat.isGroupRealismActive, isTrue, reason: 'baseline: realism');
      expect(chat.nextCharacter?.name, 'Ada', reason: 'baseline: Ada is up');
      final before = speakers().length;

      stopDuringNextRealismCheck();
      await chat.sendMessage('Evening, you two.');
      await _drain();
      expect(chat.messages.last.isUser, isTrue, reason: 'no reply written');
      expect(chat.canRetryStoppedReply, isTrue, reason: 'Try again offered');
      expect(chat.nextCharacter?.name, 'Ada', reason: 'Ada never spoke');

      await chat.regenerateLastMessage(); // the notice's Try again
      await _drain();
      expect(
        chat.messages.last.sender,
        'Ada',
        reason: 'Try again answers as the member who was stopped',
      );
      expect(chat.nextCharacter?.name, 'Bex', reason: 'Ada took her turn');

      await chat.sendMessage('How was the day?');
      await _drain();
      expect(chat.messages.last.sender, 'Bex');
      expect(speakers().skip(before), ['Ada', 'Bex'], reason: 'nobody twice');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('Bex stopped on Next, pressing Next again gives Bex the turn', () async {
    await chat.sendMessage('Evening, you two.');
    await _drain();
    expect(chat.messages.last.sender, 'Ada', reason: 'baseline: Ada first');

    stopDuringNextRealismCheck();
    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Ada', reason: 'Bex wrote nothing');
    expect(chat.nextCharacter?.name, 'Bex', reason: 'Bex is still up');

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Bex');
    expect(chat.nextCharacter?.name, 'Ada');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
