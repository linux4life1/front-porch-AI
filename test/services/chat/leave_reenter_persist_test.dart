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

// Every finished turn is written to SQLite. Back → Home → re-enter is
// only the recovery belt — the write happens when the turn is taken.
//
// Two holes produced that: (1) setActiveCharacter treated a grid card
// missing dbId as a different character, cleared `_messages`, skipped
// `_loadLastSession`, and seeded a NEW greeting session; (2) the slow
// path (or a group re-enter, or Start New Chat) discarded the live list
// before the last `_saveChat` landed, then hydrated the pre-turn row.
//
// These guards were proven red: identity test fails if the old
// `name && dbId` check is restored; persist test fails if
// `flushPendingSaves` is removed from the slow path.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
          return Directory.systemTemp
              .createTempSync('fpai_leave_reenter_')
              .path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She nods on the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentLlm';
}

class _HangingLlm extends LLMService {
  final gate = Completer<void>();

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      await gate.future;
      yield '*She nods on the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HangingLlm';
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

  CharacterCard alice({String? dbId = 'char-alice'}) => CharacterCard(
    name: 'Alice',
    description: 'Exists only for the leave/re-enter persist test.',
    firstMessage: 'The porch light hums.',
  )..dbId = dbId;

  CharacterCard bob() => CharacterCard(
    name: 'Bob',
    description: 'A second card so the slow path actually runs.',
    firstMessage: 'Evening.',
  )..dbId = 'char-bob';

  Future<void> waitForReply() async {
    for (
      var i = 0;
      i < 200 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  String swipesBlob(List<Message> rows) => rows.map((r) => r.swipes).join();

  test(
    'sendMessage writes the finished exchange to the session before it returns',
    () async {
      await chat.setActiveCharacter(alice());
      await chat.sendMessage('hello there');
      final sid = chat.currentSessionId!;
      final blob = swipesBlob(await db.getMessagesForSession(sid));
      expect(blob, contains('hello there'));
      expect(
        blob,
        contains('nods on the porch'),
        reason:
            'the reply is durable when the turn is taken, not when you '
            'leave the chat or a backup runs',
      );
    },
  );

  test('the user line is in the DB before the reply stream finishes', () async {
    final llm = _HangingLlm();
    chat.testLlmServiceOverride = llm;
    await chat.setActiveCharacter(alice());
    final send = chat.sendMessage('park this line');
    Message? found;
    for (var i = 0; i < 400; i++) {
      final sid = chat.currentSessionId;
      if (sid != null) {
        final rows = await db.getMessagesForSession(sid);
        if (swipesBlob(rows).contains('park this line')) {
          found = rows.firstWhere((r) => r.swipes.contains('park this line'));
          break;
        }
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      found,
      isNotNull,
      reason:
          'sending must persist the user turn immediately — generation '
          'is not allowed to be the thing that makes it durable',
    );
    expect(llm.gate.isCompleted, isFalse);
    llm.gate.complete();
    await send;
  });

  test('a shorter upsert cannot erase a turn that already landed', () async {
    const sid = 'sess-tail';
    await db.insertSession(
      SessionsCompanion.insert(id: sid, characterId: const Value('char-x')),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm0',
        sessionId: sid,
        position: 0,
        sender: 'Alice',
        isUser: false,
        swipes: const Value('["greeting"]'),
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm1',
        sessionId: sid,
        position: 1,
        sender: 'Linus',
        isUser: true,
        swipes: const Value('["hello"]'),
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm2',
        sessionId: sid,
        position: 2,
        sender: 'Alice',
        isUser: false,
        swipes: const Value('["reply"]'),
      ),
    );

    await db.upsertMessagesPreservingTail(sid, [
      MessagesCompanion(
        sessionId: const Value(sid),
        position: const Value(0),
        sender: const Value('Alice'),
        isUser: const Value(false),
        swipes: const Value('["greeting"]'),
      ),
    ]);

    expect(
      (await db.getMessagesForSession(sid)).length,
      3,
      reason:
          'default persist is upsert-by-position — a stale shorter '
          'snapshot must not delete the landed exchange',
    );
    expect(swipesBlob(await db.getMessagesForSession(sid)), contains('reply'));
  });

  test(
    're-enter with a dbId-less grid card keeps the live transcript',
    () async {
      await chat.setActiveCharacter(alice());
      await chat.sendMessage('hello there');
      await waitForReply();
      expect(chat.messages.length, greaterThanOrEqualTo(3));
      final before = chat.messages.map((m) => m.text).toList();

      await chat.setActiveCharacter(alice(dbId: null));

      expect(
        chat.messages.map((m) => m.text).toList(),
        before,
        reason:
            'a library card missing dbId is still Alice — must not seed a '
            'new greeting session and drop the last exchange',
      );
      expect(chat.messages.length, greaterThanOrEqualTo(3));
    },
  );

  test(
    'leave for another character then come back keeps an unsaved last exchange',
    () async {
      await chat.setActiveCharacter(alice());
      await chat.sendMessage('hello there');
      await waitForReply();
      expect(chat.messages.length, greaterThanOrEqualTo(3));
      final sid = chat.currentSessionId!;
      final kept = chat.messages.map((m) => m.text).toList();

      // Disk is missing the last exchange; memory still has it. This is
      // the leave-while-the-save-is-queued state, minus the timing.
      final greeting = await db.getMessagesForSession(sid);
      expect(greeting, isNotEmpty);
      final first = greeting.first;
      await db.deleteMessagesForSession(sid);
      await db.insertMessage(
        MessagesCompanion.insert(
          id: first.id,
          sessionId: sid,
          position: 0,
          sender: first.sender,
          isUser: first.isUser,
          swipes: Value(first.swipes),
        ),
      );
      expect((await db.getMessagesForSession(sid)).length, 1);

      await chat.setActiveCharacter(bob());
      await chat.setActiveCharacter(alice());

      expect(
        chat.messages.map((m) => m.text).toList(),
        kept,
        reason:
            'switching away must persist the live list before reload, or '
            'the last exchange is gone when you tap Alice again',
      );
      expect((await db.getMessagesForSession(sid)).length, kept.length);
    },
  );

  test(
    'Start New Chat persists the previous session\'s last exchange',
    () async {
      await chat.setActiveCharacter(alice());
      await chat.sendMessage('hello there');
      await waitForReply();
      final sid = chat.currentSessionId!;
      final keptCount = chat.messages.length;
      expect(keptCount, greaterThanOrEqualTo(3));

      final greeting = await db.getMessagesForSession(sid);
      final first = greeting.first;
      await db.deleteMessagesForSession(sid);
      await db.insertMessage(
        MessagesCompanion.insert(
          id: first.id,
          sessionId: sid,
          position: 0,
          sender: first.sender,
          isUser: first.isUser,
          swipes: Value(first.swipes),
        ),
      );

      await chat.startNewChat();

      expect(
        (await db.getMessagesForSession(sid)).length,
        keptCount,
        reason:
            'Start New Chat used to clear `_messages` without a flush, '
            'so a still-queued last exchange died with the old session',
      );
    },
  );
}
