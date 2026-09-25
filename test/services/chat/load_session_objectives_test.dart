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

// QUESTS ARE PER-CHAT, SO SWITCHING CHATS HAS TO RELOAD THEM.
//
// Objectives are keyed (character, CHAT) in the database, but `loadSession`
// — the in-chat history drawer, the home page's session picker, the
// delete-session switch, the web facade — never reloaded them. The in-memory
// list kept the PREVIOUS chat's rows, which the prompt then injected into the
// new chat while the pre-send completion check wrote back (deactivate / task
// updates, addressed by primary key) into the OTHER chat's quests. Meanwhile
// the chat you actually opened showed and injected none of its own.
//
// `_loadLastSession` carried a comment claiming "objectives there are handled
// by its own callers"; the audit found every call site bare.
//
// Proven to fail first: with the loader block removed from `loadSession`, the
// second expectation below reads "Find the lost key" — chat B running chat A's
// quest.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_objsw_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentLlm';
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
      'journal_enabled': false,
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

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('switching chats swaps the quest list with it', () async {
    final card = CharacterCard(
      name: 'Alice',
      description: 'Exists only inside the objective-switch test.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-objsw-1';
    await chat.setActiveCharacter(card);

    final chatA = chat.currentSessionId!;
    await chat.setObjective('Find the lost key');
    expect(chat.primaryObjective?.objective, 'Find the lost key');

    // A second chat with the same character — the ordinary two-chats case.
    await chat.startNewChat();
    final chatB = chat.currentSessionId!;
    expect(chatB, isNot(chatA));
    await chat.setObjective('Fix the porch swing');
    expect(chat.primaryObjective?.objective, 'Fix the porch swing');

    // Back to A through the same door the history drawer uses.
    await chat.loadSession(chatA);
    expect(
      chat.primaryObjective?.objective,
      'Find the lost key',
      reason: "chat A's quest comes back with chat A",
    );

    // ...and forward to B again. THE BUG: without a reload this still reads
    // "Find the lost key", which the prompt injects and the completion check
    // then deactivates — in chat A's rows.
    await chat.loadSession(chatB);
    expect(chat.primaryObjective?.objective, 'Fix the porch swing');
    expect(chat.secondaryObjectives, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'a chat with no quests shows none, rather than the last chat\'s',
    () async {
      final card = CharacterCard(
        name: 'Alice',
        description: 'Exists only inside the objective-switch test.',
        firstMessage: 'The porch light hums.',
      )..dbId = 'char-objsw-2';
      await chat.setActiveCharacter(card);

      final chatA = chat.currentSessionId!;
      await chat.setObjective('Find the lost key');
      await chat.startNewChat();
      final chatB = chat.currentSessionId!;

      await chat.loadSession(chatA);
      expect(chat.primaryObjective, isNotNull);
      await chat.loadSession(chatB);
      expect(
        chat.primaryObjective,
        isNull,
        reason:
            'a fresh chat has no quests; carrying the previous one over is how '
            "the other chat's rows got written by this chat's turns",
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
