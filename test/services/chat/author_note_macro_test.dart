// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE AUTHOR'S NOTE RESOLVES ITS MACROS LIKE EVERY OTHER BLOCK.
//
// The system prompt, lore, scenario, examples, post-history, objectives and
// the catastrophe wrapper all pass through the macro resolver before the
// plan renders. The Author's Note — the one block the user types during a
// chat — did not, so a `{{char}}` or `{{user}}` in the note reached the
// model as braces, on the reply path and on impersonate alike.
//
// Guard proven red before passing: without the resolver call on
// `t.authorNoteBlock` (and its impersonate twin) every assertion below that
// looks for the resolved name found the braces instead.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fpai_an_macro_');
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
      'passage_of_time_default': false,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => sandbox.path,
        );
  });
  tearDown(() async {
    await AppDatabase.closeAndReset();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('the note names the character and the user on send, Continue and '
      'impersonate', () async {
    HttpOverrides.global = null;
    final backend = await FakeBackendServer.start(
      replyPieces: ['The porch is quiet.'],
    );
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final personas = UserPersonaService(db);
    final chat =
        ChatService(
            KoboldService(storage)..setBaseUrl(backend.baseUrl),
            personas,
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    addTearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });
    final card = CharacterCard(
      name: 'Wren',
      firstMessage: 'Welcome.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'an-macro-wren';
    await chat.setActiveCharacter(card);
    chat.setAuthorNote('{{char}} keeps glancing at {{user}}', strength: 5);

    String userText() {
      final body = jsonDecode(backend.lastChatBody) as Map;
      return (body['messages'] as List)
          .where((m) => m['role'] == 'user')
          .map((m) => m['content'])
          .join('\n');
    }

    void assertResolved(String path) {
      final user = userText();
      final who = personas.persona.name.trim();
      final resolvedUser = who.isEmpty ? 'User' : who;
      expect(
        user,
        contains("[Author's Note: Wren keeps glancing at $resolvedUser]"),
        reason: '$path: the note names the speaker and the user',
      );
      expect(user, isNot(contains('{{char}}')), reason: path);
      expect(user, isNot(contains('{{user}}')), reason: path);
    }

    await chat.sendMessage('I sit down on the step.');
    assertResolved('send');
    await chat.continueGeneration();
    assertResolved('Continue');
    await chat.impersonateUser(onToken: (_) {});
    assertResolved('impersonate');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a switched-off note keeps its text, reaches no send, Continue or '
      'impersonate, survives a reload, and is sent again once on', () async {
    HttpOverrides.global = null;
    final backend = await FakeBackendServer.start(
      replyPieces: ['The porch is quiet.'],
    );
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final chat =
        ChatService(
            KoboldService(storage)..setBaseUrl(backend.baseUrl),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    addTearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });
    final card = CharacterCard(
      name: 'Wren',
      firstMessage: 'Welcome.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'an-switch-wren';
    await chat.setActiveCharacter(card);
    const note = 'ANSWITCHMARK hums on the step';
    chat.setAuthorNote(note, strength: 5);
    chat.setAuthorNoteEnabled(false);

    String prompt() => backend.lastChatBody;
    void assertNoNote(String path) {
      expect(prompt(), isNot(contains('ANSWITCHMARK')), reason: path);
      expect(prompt(), isNot(contains("Author's Note")), reason: path);
    }

    await chat.sendMessage('I sit down on the step.');
    assertNoNote('send');
    await chat.continueGeneration();
    assertNoNote('Continue');
    await chat.impersonateUser(onToken: (_) {});
    assertNoNote('impersonate');
    expect(chat.authorNote, note, reason: 'off keeps the text');

    final id = chat.currentSessionId!;
    final row = await db.getSessionById(id);
    expect(row!.authorNoteEnabled, isFalse, reason: 'the row saves the off');
    expect(row.authorNote, note);
    await chat.loadSession(id);
    expect(chat.authorNoteEnabled, isFalse, reason: 'a reload reads it back');
    expect(chat.authorNote, note);

    chat.setAuthorNoteEnabled(true);
    await chat.sendMessage('I look up.');
    expect(prompt(), contains("[Author's Note: $note]"), reason: 'on again');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
