// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create Group Chat names a new group after all of its members until the
// user types a name; it used to keep only the first member's name, so
// Juniper + Marlow saved as "Juniper". A typed name is never overwritten.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the default name lists every member, then counts past three', () {
    expect(defaultGroupName(const []), '');
    expect(defaultGroupName(const ['Juniper']), 'Juniper');
    expect(defaultGroupName(const ['Juniper', 'Marlow']), 'Juniper & Marlow');
    expect(
      defaultGroupName(const ['Juniper', 'Marlow', 'Ivy']),
      'Juniper, Marlow & Ivy',
    );
    expect(
      defaultGroupName(const ['Juniper', 'Marlow', 'Ivy', 'Rowan']),
      'Juniper & 3 others',
    );
  });

  testWidgets('the Group Name follows the roster until the user types one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cast = [
      for (final n in ['Juniper', 'Marlow', 'Ivy', 'Rowan'])
        CharacterCard(name: n, description: '$n is here.', firstMessage: 'Hi.'),
    ];
    final repo = FakeCharacterRepository(cast);
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    final folders = FakeFolderService();
    final groups = FakeGroupChatRepository();
    final llm = FakeLLMProvider();
    final tts = FakeTtsService();
    for (final s in [repo, chat, storage, worlds, folders, groups, llm, tts]) {
      addTearDown(s.dispose);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<FolderService>.value(value: folders),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<TtsService>.value(value: tts),
        ],
        child: const MaterialApp(home: CreateGroupChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text).first);
      await tester.tap(find.text(text).first);
      await tester.pumpAndSettle();
    }

    String groupName() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Group Name'))
        .controller!
        .text;

    await tapText('Juniper');
    await tapText('Marlow');
    await tapText('Next');
    expect(groupName(), 'Juniper & Marlow');

    await tapText('Back');
    await tapText('Ivy');
    await tapText('Next');
    expect(groupName(), 'Juniper, Marlow & Ivy');

    await tapText('Back');
    await tapText('Rowan');
    await tapText('Next');
    expect(groupName(), 'Juniper & 3 others');

    // A typed name is the user's: changing the roster leaves it alone.
    await tester.enterText(
      find.widgetWithText(TextField, 'Group Name'),
      'Porch Regulars',
    );
    await tester.pumpAndSettle();
    await tapText('Back');
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Current Roster (3)'), findsOneWidget);
    await tapText('Next');
    expect(groupName(), 'Porch Regulars');
  });
}
