// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Extract Characters" on a group files the copies in the folder the group
// lives in, on desktop (home card menu) and web (/api/groups/<id>/extract via
// GroupFacade). Before, every copy landed on the home top level.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/facade/group_facade.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_transfer_actions.dart';

import '../helpers/reprocess_needs_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late FolderService folders;
  late GroupChatRepository groups;

  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    folders = FolderService(h.db);
    groups = GroupChatRepository(h.storage, h.db);
  });
  tearDown(() => h.dispose());

  /// A two-member group whose members both have a private avatar on disk,
  /// optionally filed in [folderId].
  Future<GroupChat> seedGroup(String id, {String? folderId}) async {
    final avatars = Directory(p.join(h.storage.groupsDir.path, id, 'avatars'))
      ..createSync(recursive: true);
    await h.db.insertGroup(GroupsCompanion.insert(id: id, name: 'Porch'));
    for (final name in ['Juniper', 'Marlow']) {
      final file = '${name.toLowerCase()}.png';
      await V2CardService().saveCardAsPng(
        CharacterCard(name: name),
        p.join(avatars.path, file),
        null,
      );
      await h.db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: '$id-$name',
          groupId: id,
          name: name,
          avatarFilename: Value(file),
        ),
      );
    }
    if (folderId != null) await h.db.updateGroupFolderId(id, folderId);
    await groups.reload();
    await folders.reload();
    return groups.getById(id)!;
  }

  Future<Map<String, String?>> folderByName() async => {
    for (final c in await h.db.getAllCharacters()) c.name: c.folderId,
  };

  test('web: extracted members land in the group\'s folder', () async {
    final folder = await folders.createFolder('Tavern');
    await seedGroup('g1', folderId: folder.id);
    final facade = GroupFacade(groups, h.storage, h.repo, h.db, folders);

    expect(await facade.extractMembers('g1'), 2);

    final placed = await folderByName();
    expect(placed.length, 2);
    expect(placed.values, everyElement(folder.id));
    expect(folders.getCharactersInFolder(folder.id), hasLength(2));
  });

  testWidgets('desktop: Extract Characters files copies in the group folder', (
    tester,
  ) async {
    late GroupChat group;
    late String folderId;
    await tester.runAsync(() async {
      folderId = (await folders.createFolder('Tavern')).id;
      group = await seedGroup('g3', folderId: folderId);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: h.repo),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          Provider<StorageService>.value(value: h.storage),
          ChangeNotifierProvider<FolderService>.value(value: folders),
        ],
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    final context = tester.element(find.byType(SizedBox));

    await tester.runAsync(() => extractHomeGroupCharacters(context, group));
    await tester.pump();

    late Map<String, String?> placed;
    await tester.runAsync(() async => placed = await folderByName());
    expect(placed.length, 2);
    expect(placed.values, everyElement(folderId));
    expect(find.text('Extracted 2 characters as individuals.'), findsOneWidget);
  });
}
