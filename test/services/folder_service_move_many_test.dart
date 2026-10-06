// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #347: Select all can pick hundreds of cards, and the bulk move used to
// move them one at a time, each move re-reading every character, writing
// one row, then reloading every folder and redrawing the library.
// FolderService.moveMany moves the lot in one transaction and reloads once.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/folder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FolderService folders;
  const ann = '/library/Ann_1.png';
  const bo = '/library/Bo_2.png';
  const cy = '/library/Cy_3.png';

  setUp(() async {
    db = AppDatabase.forTesting();
    for (final (name, path) in [('Ann', ann), ('Bo', bo), ('Cy', cy)]) {
      await db.insertCharacterReturningId(
        CharactersCompanion(name: Value(name), imagePath: Value(path)),
      );
    }
    await db.insertGroup(GroupsCompanion.insert(id: 'group_1', name: 'Crew'));
    await db.insertGroup(GroupsCompanion.insert(id: 'group_2', name: 'Band'));
    folders = FolderService(db);
    await folders.reload();
  });

  tearDown(() async {
    folders.dispose();
    await db.close();
  });

  test('moves characters and groups together, with one reload', () async {
    final porch = await folders.createFolder('Porch');
    var notified = 0;
    folders.addListener(() => notified++);

    final moved = await folders.moveMany(
      folderId: porch.id,
      characterPaths: [ann, bo],
      groupIds: ['group_1'],
    );

    expect(moved, 3);
    expect(notified, 1, reason: 'one reload, one redraw — not one per card');
    expect(folders.getCharactersInFolder(porch.id).toSet(), {
      'Ann_1.png',
      'Bo_2.png',
    });
    expect(folders.groupIdsInFolder(porch.id), ['group_1']);
    // What was not picked stays where it was.
    expect(folders.getFolderForCharacter(cy), isNull);
    expect(folders.getFolderForGroup('group_2'), isNull);
    // It is on the rows, not only in memory.
    await folders.reload();
    expect(folders.getFolderForCharacter(ann)?.id, porch.id);
    expect((await db.getGroupById('group_1'))?.folderId, porch.id);
  });

  test('a null folder sends everything back to the top level', () async {
    final porch = await folders.createFolder('Porch');
    final nested = await folders.createFolder('Nested', parentId: porch.id);
    await folders.moveMany(folderId: porch.id, characterPaths: [ann]);
    await folders.moveMany(
      folderId: nested.id,
      characterPaths: [bo],
      groupIds: ['group_2'],
    );

    final moved = await folders.moveMany(
      folderId: null,
      characterPaths: [ann, bo],
      groupIds: ['group_2'],
    );

    expect(moved, 3);
    expect(folders.getFolderForCharacter(ann), isNull);
    expect(folders.getFolderForCharacter(bo), isNull);
    expect(folders.getFolderForGroup('group_2'), isNull);
  });

  test('unknown cards and groups are skipped and not counted', () async {
    final porch = await folders.createFolder('Porch');
    final moved = await folders.moveMany(
      folderId: porch.id,
      characterPaths: [ann, '/library/Nobody_9.png'],
      groupIds: ['group_gone'],
    );
    expect(moved, 1);
    expect(folders.getCharactersInFolder(porch.id), ['Ann_1.png']);
  });

  test('nothing to move does not touch the database or redraw', () async {
    var notified = 0;
    folders.addListener(() => notified++);
    expect(await folders.moveMany(folderId: null), 0);
    expect(notified, 0);
  });
}
