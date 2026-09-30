// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ChatSessionFacade: group listing without touching the active chat, and
// action: delete with no-replacement.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_session_facade.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_sess_facade_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late ChatSessionFacade facade;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    facade = ChatSessionFacade(chat, CharacterRepository(db, storage), () {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('list(groupId) returns that group without activating a chat', () async {
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'gs1',
        groupId: const Value('grp-1'),
        name: const Value('Porch night'),
      ),
    );

    final listed = await facade.list(groupId: 'grp-1');
    expect(listed, hasLength(1));
    expect(listed.single['id'], 'gs1');
    expect(listed.single['session_name'], 'Porch night');
    expect(chat.currentSessionId, isNull);
  });

  test(
    'delete with startReplacement false does not mint a new session',
    () async {
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'gs1',
          groupId: const Value('grp-1'),
          name: const Value('Porch night'),
        ),
      );

      final id = await facade.apply(
        action: 'delete',
        sessionId: 'gs1',
        startReplacement: false,
      );
      expect(id, isNull);
      expect(await db.getSessionById('gs1'), isNull);
      expect(chat.currentSessionId, isNull);
    },
  );
}
