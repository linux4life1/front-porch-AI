// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where we are" is a saved part of the chat. Reloading the open chat
// (model switch, settings, coming back) must not replace a live recap
// with an empty row.

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
          return Directory.systemTemp.createTempSync('fpai_recap_reload_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

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
      'journal_enabled': true,
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

  test('reloading the open chat keeps a recap the row had lost', () async {
    final card = CharacterCard(
      name: 'Mara',
      description: 'Keeps the recap.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-recap-reload';
    await chat.setActiveCharacter(card);
    const recap = 'We are on the porch. The storm has passed.';
    chat.setSummary(recap);
    await Future<void>.delayed(Duration.zero);
    final sid = chat.currentSessionId!;
    await db.patchSession(
      SessionsCompanion(id: Value(sid), summary: const Value(null)),
    );

    await chat.reloadCurrentSession();

    expect(chat.summary, recap);
    final row = await db.getSessionById(sid);
    expect(row!.summary, recap);
  });
}
