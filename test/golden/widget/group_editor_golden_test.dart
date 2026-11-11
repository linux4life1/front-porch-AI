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

@Tags(['golden'])
@TestOn('linux')
library;

// The Edit group Details tab and the member editor (top, with the notice;
// bottom, with Time & Day, Chaos Mode and Realism Verification greyed and
// the group section), under Porch and one non-Porch theme, light and dark
// (docs/design/group-editor.md E). The images are generated on the Linux CI
// image by the Update Goldens workflow (label `update-goldens`).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show GroupMemberMode;
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';
import 'package:front_porch_ai/ui/theme/app_palette.dart';
import 'package:front_porch_ai/ui/theme/app_theme.dart';
import 'package:front_porch_ai/ui/theme/themes/midnight_theme.dart';

import '../support/fakes.dart';
import '../support/fakes_storage.dart';

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

const _key = Key('group-editor-golden');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final themes = <(String, AppThemePalettes)>[
    ('porch', AppThemePalettes.porch),
    ('midnight', midnightTheme),
  ];

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function(AppDatabase db, Directory root) page, {
    double scrollTo = 0,
  }) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final (themeName, palettes) in themes) {
      for (final brightness in Brightness.values) {
        final mode = brightness == Brightness.light ? 'light' : 'dark';
        final db = AppDatabase.forTesting(sameIsolate: true);
        final root = Directory.systemTemp.createTempSync('fpai_gold');
        final storage = _Storage(root);
        await db.insertGroup(
          GroupsCompanion.insert(
            id: 'g',
            name: 'The Porch Trio',
            personality: const Value('Close, teasing and loyal.'),
          ),
        );
        for (final n in ['Ana', 'Bea']) {
          await db.insertGroupMember(
            GroupMembersCompanion.insert(id: 'mem-$n', groupId: 'g', name: n),
          );
        }
        final chat = FakeChatService();
        final worlds = FakeWorldRepository();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<GroupChatRepository>.value(
                value: GroupChatRepository(storage, db),
              ),
              ChangeNotifierProvider<CharacterRepository>.value(
                value: _Library(),
              ),
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<WorldRepository>.value(value: worlds),
              ChangeNotifierProvider<FolderService>.value(
                value: FakeFolderService(),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(palettes: palettes, brightness: brightness),
              home: RepaintBoundary(key: _key, child: page(db, root)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scrollTo > 0) {
          final scrollable = find.byType(Scrollable).first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(scrollTo);
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byKey(_key),
          matchesGoldenFile('_goldens/group_editor/$name.$themeName.$mode.png'),
        );
        await tester.pumpWidget(const SizedBox());
        chat.dispose();
        worlds.dispose();
        await db.close();
        root.deleteSync(recursive: true);
      }
    }
  }

  GroupMemberMode mode() => GroupMemberMode(
    groupName: 'The Porch Trio',
    memberId: 'mem-Ana',
    others: const [GroupMemberRef('mem-Bea', 'Bea')],
    scene: const GroupSceneTime(),
    values: const GroupMemberValues(),
    saveValues: (_) async {},
  );

  CharacterCard ana() =>
      CharacterCard(
          name: 'Ana',
          description: 'Runs the hardware store on Main Street.',
        )
        ..dbId = 'mem-Ana'
        ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true);

  testWidgets('Edit group, Details tab', (tester) async {
    await shoot(
      tester,
      'edit_group_details',
      (db, root) => EditGroupPage(
        group: GroupChat(
          id: 'g',
          name: 'The Porch Trio',
          personality: 'Close, teasing and loyal.',
        ),
      ),
    );
  });

  testWidgets('member editor, top (the notice)', (tester) async {
    await shoot(
      tester,
      'member_top',
      (db, root) => EditCharacterPage(character: ana(), member: mode()),
    );
  });

  testWidgets('member editor, bottom (greyed controls, the group section)', (
    tester,
  ) async {
    await shoot(
      tester,
      'member_bottom',
      (db, root) => EditCharacterPage(character: ana(), member: mode()),
      scrollTo: 6000,
    );
  });
}
