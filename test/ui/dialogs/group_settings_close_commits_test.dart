// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings X and footer Close used to Navigator.pop without applying
// General. Name / scenario / opening / turn rules sat in controllers, so
// renaming a group and hitting X threw the rename away with no warning.
// Done already commits (group_settings_done_commits_test). This is the twin:
// dirty Close/X warn; Save on the warning applies; Discard leaves the old name.
//
// Proven red: restore a bare Navigator.pop on Close and the Save-on-warning
// assertion fails (live group still 'The Fellowship').

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';

import '../../golden/support/fakes.dart';

class _ChatWithGroup extends FakeChatService {
  _ChatWithGroup(this._group);
  final GroupChat _group;

  @override
  GroupChat? get activeGroup => _group;
}

class _RecordingRepo extends FakeGroupChatRepository {
  GroupChat? saved;

  @override
  Future<void> save(GroupChat group) async {
    saved = group;
  }
}

Future<({GroupChat group, _RecordingRepo repo})> _pumpRenamed(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final group = GroupChat(id: 'g1', name: 'The Fellowship');
  final chat = _ChatWithGroup(group);
  final repo = _RecordingRepo();
  final worlds = FakeWorldRepository();
  addTearDown(chat.dispose);
  addTearDown(repo.dispose);
  addTearDown(worlds.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatService>.value(value: chat),
        ChangeNotifierProvider<WorldRepository>.value(value: worlds),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: GroupSettingsDialog(chatService: chat, groupRepo: repo),
        ),
      ),
    ),
  );
  await tester.pump();

  final generalTab = find.text('General');
  await tester.ensureVisible(generalTab);
  await tester.tap(generalTab);
  await tester.pumpAndSettle();

  expect(find.byType(GroupGeneralTab), findsOneWidget);

  final nameField = find
      .descendant(
        of: find.byType(GroupGeneralTab),
        matching: find.byType(TextField),
      )
      .first;
  await tester.enterText(nameField, 'The New Fellowship');
  await tester.pump();

  expect(group.name, 'The Fellowship');
  return (group: group, repo: repo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Close warns when General is dirty; Save on the warning applies',
    (tester) async {
      final h = await _pumpRenamed(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved General changes'), findsOneWidget);
      expect(h.group.name, 'The Fellowship');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(h.group.name, 'The New Fellowship');
      expect(h.repo.saved, same(h.group));
      expect(find.text('Unsaved General changes'), findsNothing);
    },
  );

  testWidgets('Close warns; Discard leaves the live group untouched', (
    tester,
  ) async {
    final h = await _pumpRenamed(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(h.group.name, 'The Fellowship');
    expect(h.repo.saved, isNull);
  });

  testWidgets('header X warns the same way; Save on the warning applies', (
    tester,
  ) async {
    final h = await _pumpRenamed(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved General changes'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(h.group.name, 'The New Fellowship');
    expect(h.repo.saved, same(h.group));
  });

  testWidgets('Close with a clean General tab pops without a warning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final group = GroupChat(id: 'g1', name: 'The Fellowship');
    final chat = _ChatWithGroup(group);
    final repo = _RecordingRepo();
    final worlds = FakeWorldRepository();
    addTearDown(chat.dispose);
    addTearDown(repo.dispose);
    addTearDown(worlds.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupSettingsDialog(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved General changes'), findsNothing);
    expect(group.name, 'The Fellowship');
    expect(repo.saved, isNull);
  });
}
