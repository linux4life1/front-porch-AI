// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A 1:1 chat's Chaos "spicy events" switch survives a reload (v56 column).
// Before v56 the switch was never saved, so it read back off — or, on the
// history-picker path, whatever the previously open chat had left behind.

import 'dart:io';

import 'package:drift/drift.dart' show Migrator, Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_chaos_spicy_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  DebugPrintCallback? previousPrint;

  setUp(() async {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  Future<Object?> column(String name, String sessionId) async {
    final row = await db
        .customSelect(
          'SELECT $name AS v FROM sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingle();
    return row.data['v'];
  }

  test('the 1:1 spicy switch is saved and read back on reload', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        imagePath: 'chaos-spicy-mara.png',
      )..dbId = 'char-chaos-spicy',
    );
    await chat.setChaosModeEnabled(true);
    await chat.setChaosNsfwEnabled(true);
    final id = chat.currentSessionId!;
    expect(await column('chaos_nsfw_enabled', id), 1);

    // Something else flips the in-memory value (the old bleed); the reload
    // must restore what this chat saved.
    chat.chaosModeService.setNsfwEnabled(false);
    await chat.reloadCurrentSession();
    expect(chat.chaosNsfwEnabled, isTrue);
  });

  test('the v56 step adds the column, off for every existing row', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Ivo',
        firstMessage: 'Rain on the tin roof.',
        imagePath: 'chaos-spicy-ivo.png',
      )..dbId = 'char-chaos-spicy-2',
    );
    await chat.setChaosModeEnabled(true);
    final id = chat.currentSessionId!;
    await db.customStatement(
      'ALTER TABLE sessions DROP COLUMN chaos_nsfw_enabled',
    );
    await db.migration.onUpgrade(Migrator(db), 55, db.schemaVersion);
    expect(await column('chaos_nsfw_enabled', id), 0);
    // Re-running the step is harmless.
    await db.migration.onUpgrade(Migrator(db), 55, db.schemaVersion);
    expect(await column('chaos_nsfw_enabled', id), 0);
  });
}
