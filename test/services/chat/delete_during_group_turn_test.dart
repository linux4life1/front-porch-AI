// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A finished group speaker can be deleted while the next speaker is still
// generating. The tail (the live reply) stays put — positional writers
// still assume it is last. An earlier blank "Thinking…" bubble must not
// be stuck until that reply finishes.

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
          return Directory.systemTemp.createTempSync('fpai_grp_del_').path;
        }
        return null;
      });
}

class _HangSecondMouth extends LLMService {
  Completer<void>? hang;
  int calls = 0;

  @override
  void abortGeneration() {
    final pending = hang;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    calls++;
    // Realism is off, so each speaker is one mouth call. The second
    // speaker stays open so the test can delete the first reply.
    // The completer is created HERE: generation aborts any previous
    // call before the mouth starts, and that must not release this hang.
    if (calls == 1) {
      yield 'Iris answers.';
      return;
    }
    if (calls == 2) {
      final gate = hang = Completer<void>();
      yield '<think>still planning the scene';
      await gate.future;
      return;
    }
    yield '{}';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HangSecondMouth';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late _HangSecondMouth llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'needs_sim_default': false,
      'journal_enabled': false,
      'passage_of_time_default': false,
    });
    db = AppDatabase.forTesting();
    final storage = StorageService();
    llm = _HangSecondMouth();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-del', name: 'Sophia & Iris'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-iris',
        groupId: 'grp-del',
        name: 'Iris',
        firstMessage: const Value(''),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-sophia',
        groupId: 'grp-del',
        name: 'Sophia',
        firstMessage: const Value(''),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-del', name: 'Sophia & Iris'),
      groupRepo: GroupChatRepository(storage, db),
    );
    for (var i = 0; i < 40 && chat.groupCharacters.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });

  tearDown(() async {
    llm.abortGeneration();
    await disposeChatThenCloseDb(chat, db);
  });

  Future<void> waitUntil(bool Function() pred) async {
    for (var i = 0; i < 250 && !pred(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test(
    'an earlier group reply can be deleted while the next speaker generates',
    () async {
      final first = chat.sendMessage('Say something.');
      await waitUntil(() => llm.calls >= 1 && !chat.isGenerating);
      await first;
      expect(chat.messages.any((m) => m.text.contains('Iris answers')), isTrue);

      final second = chat.triggerNextCharacter();
      await waitUntil(
        () => chat.isGenerating && llm.calls >= 2 && chat.messages.length >= 2,
      );
      expect(chat.isGenerating, isTrue, reason: 'Sophia is still generating');

      final irisAt = chat.messages.indexWhere(
        (m) => m.text.contains('Iris answers'),
      );
      expect(irisAt, greaterThanOrEqualTo(0));
      expect(irisAt, lessThan(chat.messages.length - 1));
      final tailBefore = chat.messages.last;

      chat.deleteMessage(irisAt);
      await waitUntil(
        () => !chat.messages.any((m) => m.text.contains('Iris answers')),
      );

      expect(
        chat.messages.any((m) => m.text.contains('Iris answers')),
        isFalse,
        reason: 'the finished speaker must leave while the next one generates',
      );
      expect(identical(chat.messages.last, tailBefore), isTrue);

      final tailIndex = chat.messages.length - 1;
      chat.deleteMessage(tailIndex);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        identical(chat.messages.last, tailBefore),
        isTrue,
        reason: 'the live reply stays until Stop',
      );

      llm.abortGeneration();
      await second;
    },
  );
}
