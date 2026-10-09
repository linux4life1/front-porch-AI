// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Maintainer ruling: a new group does not inherit its members' lorebooks
// unless the user turns it on. Every way a group gets the value starts off:
// the model (wizard, fork-to-group, phone create all build a GroupChat),
// stored JSON without the field, a Group Card without the field, a raw row
// on a fresh library, and a save through the repository. A group that
// already saved "on" keeps it.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_inherit_').path;
        }
        return null;
      });

  test('a GroupChat built in code starts off', () {
    expect(GroupChat(id: 'g', name: 'G').inheritCharacterLorebooks, isFalse);
  });

  test('stored group JSON without the field reads off; a saved on stays', () {
    expect(
      GroupChat.fromJson({'id': 'g', 'name': 'G'}).inheritCharacterLorebooks,
      isFalse,
    );
    expect(
      GroupChat.fromJson({
        'id': 'g',
        'name': 'G',
        'inherit_character_lorebooks': true,
      }).inheritCharacterLorebooks,
      isTrue,
    );
  });

  test('a Group Card without the field imports off; one with it keeps it', () {
    expect(
      GroupCard.fromJson({'name': 'G'}).inheritCharacterLorebooks,
      isFalse,
    );
    expect(
      GroupCard.fromJson({
        'name': 'G',
        'inherit_character_lorebooks': true,
      }).inheritCharacterLorebooks,
      isTrue,
    );
  });

  group('library', () {
    late AppDatabase db;
    late StorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.initialized;
    });
    tearDown(() => db.close());

    test('a raw row on a fresh library starts off', () async {
      await db.insertGroup(GroupsCompanion.insert(id: 'raw', name: 'Raw'));
      final row = await db.getGroupById('raw');
      expect(row!.inheritCharacterLorebooks, isFalse);
    });

    test('a repository save keeps what the group says', () async {
      final repo = GroupChatRepository(storage, db);
      await repo.save(GroupChat(id: 'new', name: 'New'));
      await repo.save(
        GroupChat(id: 'kept', name: 'Kept', inheritCharacterLorebooks: true),
      );
      expect(
        (await db.getGroupById('new'))!.inheritCharacterLorebooks,
        isFalse,
      );
      expect(
        (await db.getGroupById('kept'))!.inheritCharacterLorebooks,
        isTrue,
      );
      repo.dispose();
    });
  });
}
