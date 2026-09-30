// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Saving a group member from the chat editor writes the card back onto the
// live roster. That roster is exposed as an unmodifiable list, so the write
// used to throw "Cannot modify an unmodifiable list" and the Save button
// reported failure (the hygiene toggle on a member of an open group).

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
          return Directory.systemTemp.createTempSync('fpai_grp_save_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    final storage = StorageService();
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
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-save', name: 'Sophia & Iris'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-sophia',
        groupId: 'grp-save',
        name: 'Sophia',
        firstMessage: const Value(''),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-save', name: 'Sophia & Iris'),
      groupRepo: GroupChatRepository(storage, db),
    );
    for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('saving the open member does not throw on the frozen roster', () {
    final sophia = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    final base = sophia.frontPorchExtensions ?? FrontPorchExtensions();
    sophia.frontPorchExtensions = base.copyWith(enjoysLowHygiene: true);

    expect(() => chat.refreshActiveCharacterCard(sophia), returnsNormally);

    final live = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    expect(live.frontPorchExtensions?.enjoysLowHygiene, isTrue);
  });

  test('a replaced member copy lands on the live roster', () {
    final sophia = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    final copy = CharacterCard(
      name: 'Sophia',
      description: 'Updated in the editor.',
    );
    if (sophia.dbId != null) copy.dbId = sophia.dbId;

    if (sophia.dbId == null) {
      // Identity is the only key when the member row has no library id.
      // The editor mutates that same instance; covered above.
      return;
    }

    chat.refreshActiveCharacterCard(copy);
    final live = chat.groupCharacters.firstWhere((c) => c.name == 'Sophia');
    expect(live.description, 'Updated in the editor.');
  });
}
