// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Impersonate-from-a-typed-prefix (Discord 2026-08-15): empty box works;
// a start already in the composer looks like a finished user turn and the
// card's "do not decide for {{user}}" wins, so the model writes the
// character. New file — test-integrity blocks edits to existing tests.
//
// Proven red: drop impersonateIdentityBlock from the system prompt →
// the prefix prompt test fails (no IMPERSONATE / SUSPENDED).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_impersonate_').path;
        }
        return null;
      });
}

Future<({AppDatabase db, ChatService chat})> _buildChat(
  OpenRouterService llm,
) async {
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': false,
  });
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
        ..testLlmServiceOverride = llm;
  await storage.initialized;
  await chat.setActiveCharacter(
    CharacterCard(
      name: 'Mara',
      description: 'A porch regular.',
      firstMessage: 'The porch light hums.',
      systemPrompt:
          'You are Mara. Do not decide for {{user}}. Never write the user\'s lines.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-impersonate-prefix',
  );
  return (db: db, chat: chat);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('identity suspends the card rule; prefix is a user-line continue', () {
    final identity = impersonateIdentityBlock(
      userName: 'Alex',
      characterName: 'Mara',
    );
    expect(identity, contains('IMPERSONATE'));
    expect(identity, contains('SUSPENDED'));
    expect(identity, contains('You are Alex'));
    expect(identity, contains('You are NOT Mara'));

    expect(
      impersonatePrefixRule(
        userName: 'Alex',
        characterName: 'Mara',
        prefix: '',
      ),
      isEmpty,
    );
    final rule = impersonatePrefixRule(
      userName: 'Alex',
      characterName: 'Mara',
      prefix: 'I walk toward the rail',
    );
    expect(rule, contains('incomplete message'));
    expect(rule, contains('NEVER write'));
    expect(rule, contains('Mara'));

    expect(impersonateSuffix(userName: 'Alex', prefix: ''), '\nAlex:');
    expect(
      impersonateSuffix(userName: 'Alex', prefix: 'I walk toward the rail'),
      '\nAlex: I walk toward the rail',
    );
  });

  test('trimAtFirstStop cuts a character-label bleed', () {
    expect(
      trimAtFirstStop('I open the door.\nMara: she smiles', ['\nMara:']),
      'I open the door.',
    );
    expect(trimAtFirstStop('just me', ['\nMara:']), 'just me');
  });

  test(
    'impersonate with a typed prefix puts identity in system and the start in the suffix',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: [' and sit down on the steps.'],
      );
      final llm = OpenRouterService(
        apiUrl: '${backend.baseUrl}/v1',
        modelName: 'smoke-model',
      );
      final h = await _buildChat(llm);
      addTearDown(() async {
        h.chat.dispose();
        await backend.close();
        await h.db.close();
      });

      await h.chat.sendMessage('Evening.');
      var seen = '';
      await h.chat.impersonateUser(
        prefix: 'I walk toward the rail',
        onToken: (a) => seen = a,
      );

      final body = jsonDecode(backend.lastChatBody) as Map;
      final messages = body['messages'] as List;
      final system = messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'] as String)
          .join('\n');
      final user = messages.last['content'] as String;

      expect(system, contains('IMPERSONATE'));
      expect(system, contains('SUSPENDED'));
      expect(system, contains('Do not decide for'));
      expect(user, contains('incomplete message'));
      expect(user, contains('I walk toward the rail'));
      expect(user, isNot(contains('Do not decide for {{user}}')));
      expect(seen, contains('I walk toward the rail'));
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
