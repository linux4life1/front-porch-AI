// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The Edit group page (docs/design/group-editor.md B): the sections in the
// spec's order over a seeded group, one write on Save, the removed controls
// absent, and the cast changed on the group's rows with its chat closed.

import 'dart:io';

import 'package:drift/drift.dart' show TableUpdateQuery, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/double_tap.dart';

class _Storage extends FakeStorageService {
  _Storage(this.root);
  final Directory root;
  @override
  Directory get groupsDir => root;
  @override
  Future<void> get initialized async {}
}

class _Library extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory root;
  late _Storage storage;
  late GroupChatRepository groups;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    root = Directory.systemTemp.createTempSync('fpai_editgroup');
    storage = _Storage(root);
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'g',
        name: 'The Porch Trio',
        personality: const Value('Close and teasing.'),
      ),
    );
    Directory('${root.path}/g/avatars').createSync(recursive: true);
    for (final n in ['Ana', 'Bea', 'Cy']) {
      File(
        '${root.path}/g/avatars/${n.toLowerCase()}.png',
      ).writeAsBytesSync([0]);
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-${n.toLowerCase()}',
          groupId: 'g',
          name: n,
          avatarFilename: Value('${n.toLowerCase()}.png'),
        ),
      );
    }
    groups = GroupChatRepository(storage, db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final chat = FakeChatService();
    final worlds = FakeWorldRepository();
    addTearDown(chat.dispose);
    addTearDown(worlds.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<CharacterRepository>.value(value: _Library()),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<FolderService>.value(
            value: FakeFolderService(),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => EditGroupPage(
                    group: GroupChat(
                      id: 'g',
                      name: 'The Porch Trio',
                      personality: 'Close and teasing.',
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // The roster reads real files.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('the Details sections come in the spec order, over the four '
      'tabs of the character editor', (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      expect(find.text('Edit The Porch Trio'), findsOneWidget);
      for (final t in ['Details', 'Dialogue', 'Lorebook', 'Worlds']) {
        expect(find.text(t), findsWidgets);
      }
      double y(String text) => tester.getTopLeft(find.text(text).first).dy;
      final order = [
        'Identity',
        'Turns',
        'Voice',
        'Personality & World',
        'Advanced Prompts',
        'Tags',
        'Realism Engine',
      ];
      for (var i = 1; i < order.length; i++) {
        await tester.ensureVisible(find.text(order[i]).first);
        await tester.pump();
      }
      final ys = <double>[];
      for (final s in order) {
        ys.add(
          tester.getTopLeft(find.text(s).first).dy +
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .pixels,
        );
      }
      expect(
        ys,
        orderedEquals([...ys]..sort()),
        reason: 'sections out of order',
      );
      expect(y('Identity'), isNonNegative);
      expect(find.text("Edit Ana's card"), findsOneWidget);
      expect(find.text('+ Add a character'), findsOneWidget);
    });
  });

  testWidgets('removed controls are absent', (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      for (final gone in [
        'Reset ALL',
        'Reset',
        'Memories per turn',
        'Memory budget',
        'Per-Character Memory Importance',
        'Needs Simulation (group)',
      ]) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });
  });

  testWidgets('Save writes the group row once', (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      var writes = 0;
      final sub = db
          .tableUpdates(TableUpdateQuery.onTable(db.groups))
          .listen((_) => writes++);
      addTearDown(sub.cancel);
      await tester.enterText(
        find.widgetWithText(TextField, 'Close and teasing.'),
        'Close, teasing and loyal.',
      );
      await tester.pump();
      await doubleTapNoFrame(tester, find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        (await db.getGroupById('g'))!.personality,
        'Close, teasing and loyal.',
      );
      expect(writes, 1, reason: 'a double tap wrote the group twice');
    });
  });

  testWidgets('the cast changes on the group rows with its chat closed, and '
      'a removed member can be brought back', (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      expect(find.text('Bring back a removed member'), findsOneWidget);
      // Nobody removed yet: greyed out with the reason.
      expect(
        tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message),
        contains('No removed members to bring back.'),
      );
      await tester.tap(find.text('Remove…').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Remove'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect((await db.getGroupMembers('g')), hasLength(2));
      await tester.tap(find.text('Bring back a removed member'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect((await db.getGroupMembers('g')), hasLength(3));
    });
  });
}
