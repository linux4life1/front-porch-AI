// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit Group used to throw away every unsaved edit on back. It now asks when
// anything Save would write has changed, leaves quietly when nothing has,
// and Save itself never asks. Its lore entries open the shared entry editor,
// which keeps imported fields and asks before dropping typed text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

const _question = 'Discard unsaved changes?';

class _RecordingGroups extends FakeGroupChatRepository {
  GroupChat? saved;
  @override
  Future<void> save(GroupChat group) async => saved = group;

  @override
  Future<List<GroupMember>> getMembersForGroup(String groupId) async =>
      const [];
}

Future<_RecordingGroups> _openEditGroup(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final group = GroupChat(
    id: 'g1',
    name: 'Porch Regulars',
    stableId: 'Porch_Regulars_123',
    groupLorebook:
        '{"entries":[{"name":"Harbor","keys":["harbor"],"content":"Fog.",'
        '"probability":40}]}',
  );
  final groups = _RecordingGroups();
  final chat = FakeChatService();
  final storage = FakeStorageService();
  final worlds = FakeWorldRepository();
  final characters = FakeCharacterRepository([]);
  for (final s in [groups, chat, storage, worlds, characters]) {
    addTearDown(s.dispose);
  }
  // Never opened (only a member edit touches it), so never closed: drift's
  // close wall-hangs under testWidgets.
  final database = db.AppDatabase.forTesting();

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
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditGroupPage(group: group),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(find.text('Edit Group'), findsOneWidget);
  return groups;
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('back from an untouched group leaves without asking', (
    tester,
  ) async {
    await _openEditGroup(tester);
    await _back(tester);
    expect(find.text(_question), findsNothing);
    expect(find.text('Edit Group'), findsNothing);
  });

  testWidgets('a renamed group asks on back; Save leaves without asking', (
    tester,
  ) async {
    final groups = await _openEditGroup(tester);
    await tester.enterText(find.byType(EditableText).first, 'Night Owls');
    await tester.pump();

    await _back(tester);
    expect(find.text(_question), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Edit Group'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);

    await tester.tap(find.text('Save'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text(_question), findsNothing);
    expect(groups.saved?.name, 'Night Owls');
    expect(find.text('Edit Group'), findsNothing);
  });

  testWidgets('a lore entry edit keeps its imported fields', (tester) async {
    final groups = await _openEditGroup(tester);
    await tester.tap(find.text('Lore & Worlds'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Edit Lorebook Entry'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Fog.'),
      'Fog, thick.',
    );
    await tester.tap(find.text('Save').last);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Save'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final book = groups.saved!.groupLorebook;
    expect(book, contains('Fog, thick.'));
    expect(book, contains('"probability":40'));
  });
}
