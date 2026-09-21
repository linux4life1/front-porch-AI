// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regen with an empty reason is today's regen (no critique section). A
// non-empty reason injects clip + reason before Name:, is not stored as a
// chat row, and Continue never sees the slip.

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
          return Directory.systemTemp
              .createTempSync('fpai_regen_critique_')
              .path;
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
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['He stands at the window ', 'and names every Sternritter.'],
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
        name: 'Mara',
        description: 'Exists only inside the regen-critique turn test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-critique',
    );
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  Future<void> _userTurn() async {
    await chat.sendMessage('Tell me about the Wandenreich.');
    expect(chat.messages.last.isUser, isFalse);
  }

  test('empty regen leaves no critique section in the prompt', () async {
    await _userTurn();
    await chat.regenerateLastMessage();
    expect(chat.lastPromptSections.containsKey('Regen Critique'), isFalse);
    expect(backend.lastChatBody, isNot(contains('Critique:')));
    expect(backend.lastChatBody, isNot(contains('Rejected take (clip):')));
  });

  test(
    'non-empty regen injects clip + reason before suffix and not into rows',
    () async {
      await _userTurn();
      const reason = 'too much lecture, talk like a book, not a wiki dump';
      await chat.regenerateLastMessage(critique: reason);

      final section = chat.lastPromptSections['Regen Critique'];
      expect(section, isNotNull);
      expect(section, contains(reason));
      expect(section, contains('stands at the window'));
      expect(section!.toLowerCase(), isNot(contains('<think>')));

      final body = backend.lastChatBody;
      final reasonAt = body.indexOf(reason);
      final suffixAt = body.lastIndexOf('Mara:');
      expect(reasonAt, greaterThanOrEqualTo(0));
      expect(
        suffixAt,
        greaterThan(reasonAt),
        reason: 'the slip must sit before the speaker prefix',
      );

      for (final m in chat.messages) {
        expect(
          m.text,
          isNot(contains(reason)),
          reason: 'critique is a prompt slip, not a stored user/assistant row',
        );
      }
    },
  );

  test('Continue after a critiqued regen does not keep the slip', () async {
    await _userTurn();
    const reason = 'too much lecture, talk like a book, not a wiki dump';
    await chat.regenerateLastMessage(critique: reason);
    expect(chat.lastPromptSections.containsKey('Regen Critique'), isTrue);

    await chat.continueGeneration();
    expect(chat.lastPromptSections.containsKey('Regen Critique'), isFalse);
    expect(backend.lastChatBody, isNot(contains(reason)));
    expect(backend.lastChatBody, isNot(contains('Rejected take (clip):')));
  });
}
