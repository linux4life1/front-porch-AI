// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Move to folder (POST /api/characters/move -> bulkMove) used to
// move one card at a time, and every move re-read the characters, reloaded
// every folder and told the library to redraw (and the phone to refetch).
// It now goes through FolderService.moveMany like the desktop: one
// transaction, one reload. Same result for the user.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_library_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late GroupChatRepository groups;
  late FolderService folders;
  late CharacterLibraryFacade facade;
  late List<String> ids;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai_bulk_move_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    ids = [
      for (final name in ['Ann', 'Bo', 'Cy', 'Dee'])
        await db.insertCharacterReturningId(
          CharactersCompanion(name: Value(name), imagePath: Value('$name.png')),
        ),
    ];
    await db.insertGroup(
      GroupsCompanion.insert(id: 'group_crew', name: 'Crew'),
    );
    repo = CharacterRepository(db, storage);
    while (repo.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    groups = GroupChatRepository(storage, db);
    await groups.reload();
    folders = FolderService(db);
    await folders.reload();
    facade = CharacterLibraryFacade(repo, folders, storage, groups);
  });

  tearDown(() async {
    folders.dispose();
    groups.dispose();
    repo.dispose();
    storage.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  test(
    'moving several cards from the phone is one reload, not one per card',
    () async {
      final porch = await folders.createFolder('Porch');
      var reloads = 0;
      folders.addListener(() => reloads++);

      final moved = await facade.bulkMove([
        ...ids.take(3),
        'group_crew',
      ], porch.id);

      expect(moved, 4);
      expect(reloads, 1, reason: 'one reload for the whole move');
      expect(folders.getCharactersInFolder(porch.id).toSet(), {
        'Ann.png',
        'Bo.png',
        'Cy.png',
      });
      expect(folders.groupIdsInFolder(porch.id), ['group_crew']);
      expect(folders.getFolderForCharacter('Dee.png'), isNull);
    },
  );

  test('back to the top level, unknown ids skipped, a bad folder moves '
      'nothing — as one by one did', () async {
    final porch = await folders.createFolder('Porch');
    await facade.bulkMove(ids, porch.id);

    // '' is the phone's "Home (no folder)".
    expect(await facade.bulkMove([ids[0], 'nope', 'group_gone'], ''), 1);
    expect(folders.getFolderForCharacter('Ann.png'), isNull);

    expect(await facade.bulkMove([ids[1]], 'not-a-folder'), 0);
    expect(folders.getFolderForCharacter('Bo.png')?.id, porch.id);
  });
}
