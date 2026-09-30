// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where we are" lives on the chat row. A save that runs before that
// text has been loaded — model switch, quit, reopen — must not blank it.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/recap_injection.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_recap_reopen_').path;
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

ChatService _chat(AppDatabase db, StorageService storage) {
  return ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )
    ..setDatabase(db)
    ..setCharacterRepository(CharacterRepository(db, storage))
    ..testLlmServiceOverride = _SilentLlm();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('an unloaded recap is left on the row', () {
    const stored = 'We are on the porch. The storm has passed.';
    final kept = recapColumnsForSave(
      boundToThisSession: false,
      clearArmed: false,
      memory: '',
      memoryCursor: 0,
      stored: stored,
      storedCursor: 40,
    );
    expect(kept.text, stored);
    expect(kept.cursor, 40);
  });

  test('a loaded clear is allowed to blank the row', () {
    final cleared = recapColumnsForSave(
      boundToThisSession: true,
      clearArmed: true,
      memory: '',
      memoryCursor: 12,
      stored: 'The old recap.',
      storedCursor: 40,
    );
    expect(cleared.text, isNull);
    expect(cleared.cursor, 12);
  });

  test('quit and reopen restores the saved recap', () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': true,
    });
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final first = _chat(db, storage);
    ChatService? second;
    addTearDown(() async {
      second?.dispose();
      await disposeChatThenCloseDb(null, db);
    });

    final card = CharacterCard(
      name: 'Mara',
      description: 'Keeps the recap across a restart.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-recap-reopen';
    await first.setActiveCharacter(card);
    const recap = 'We are on the porch. The storm has passed.';
    first.setSummary(recap);
    await first.flushPendingSaves();
    final sid = first.currentSessionId!;
    expect((await db.getSessionById(sid))!.summary, recap);

    first.dispose();
    second = _chat(db, storage);
    await second!.setActiveCharacter(card);

    expect(second.summary, recap);
    expect((await db.getSessionById(sid))!.summary, recap);
  });
}
