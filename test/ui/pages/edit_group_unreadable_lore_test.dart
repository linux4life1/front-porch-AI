// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit Group with a stored group lorebook that cannot be read. It used to
// open as an empty list with no word, and adding one entry then saving
// replaced the whole stored book with that entry. Now the tab says the
// book can't be read, and Save asks before replacing it: "Keep old
// lorebook" saves everything else and leaves the stored text as it was.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RecordingGroups extends FakeGroupChatRepository {
  GroupChat? saved;
  @override
  Future<void> save(GroupChat group) async {
    saved = group;
  }

  @override
  Future<List<GroupMember>> getMembersForGroup(String groupId) async =>
      const [];
}

const _broken = '{"entries": [ {"keys": ["well"], "content": "dry';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_RecordingGroups> openLoreTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final group = GroupChat(
      id: 'g1',
      name: 'Porch Duet',
      firstMessage: 'Evening.',
      groupLorebook: _broken,
    );
    final groups = _RecordingGroups();
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    final characters = FakeCharacterRepository([]);
    // Never opened (only a member edit touches it); see the interaction net.
    final database = db.AppDatabase.forTesting();
    for (final s in [groups, chat, storage, worlds, characters]) {
      addTearDown(s.dispose);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<CharacterRepository>.value(value: characters),
          Provider<db.AppDatabase>.value(value: database),
        ],
        child: MaterialApp(home: EditGroupPage(group: group)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Lore & Worlds'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    return groups;
  }

  Future<void> addOak(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Add Entry'));
    await tester.tap(find.text('Add Entry'));
    await tester.pump(const Duration(milliseconds: 300));
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(fields.at(0), 'Old Oak');
    await tester.enterText(fields.at(1), 'oak, tree');
    await tester.enterText(fields.at(2), 'Three hundred years old.');
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the tab says the book cannot be read', (tester) async {
    await openLoreTab(tester);
    expect(find.text(kEditGroupUnreadableLoreNote), findsOneWidget);
  });

  testWidgets('adding an entry and saving does not quietly wipe the book', (
    tester,
  ) async {
    final groups = await openLoreTab(tester);
    await addOak(tester);
    await save(tester);

    expect(find.text('Replace the old lorebook?'), findsOneWidget);
    await tester.tap(find.text('Keep old lorebook'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(groups.saved, isNotNull);
    expect(groups.saved!.groupLorebook, _broken);
  });

  testWidgets('Replace it is the only way the old text goes', (tester) async {
    final groups = await openLoreTab(tester);
    await addOak(tester);
    await save(tester);
    await tester.tap(find.text('Replace it'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(groups.saved!.groupLorebook, contains('Old Oak'));
    expect(groups.saved!.groupLorebook, isNot(contains('"dry')));
  });
}
