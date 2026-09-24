// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create-group member cards must wire Pace and per-need on/off the same way
// edit-group's GroupMemberRealismEditor does. NeedsFormSection already draws
// the controls; without the callbacks they stay inert.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create-group member card Pace and per-need switches are live', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final aerin = CharacterCard(
      name: 'Aerin',
      description: 'First roster member.',
      firstMessage: 'Hello.',
    );
    final bo = CharacterCard(
      name: 'Bo',
      description: 'Second roster member.',
      firstMessage: 'Hi.',
    );

    final repo = FakeCharacterRepository([aerin, bo]);
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

    await tester.tap(find.text('Aerin').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bo').first);
    await tester.pumpAndSettle();

    Future<void> next(String landmark) async {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(landmark), findsWidgets);
    }

    await next('Group Name');
    await tester.enterText(find.byType(TextField).first, 'Pace Probe');
    await tester.pumpAndSettle();
    await next('Group System Prompt');
    await next('Add Entry');
    await next('Day Number');

    await tester.ensureVisible(find.text('Aerin').last);
    await tester.tap(find.text('Aerin').last);
    await tester.pumpAndSettle();

    expect(find.byType(NeedsFormSection), findsWidgets);

    final pace = find.byType(SegmentedButton<String>).first;
    await tester.ensureVisible(pace);
    expect(
      tester.widget<SegmentedButton<String>>(pace).onSelectionChanged,
      isNotNull,
      reason: 'create-group must wire onNeedsPaceChanged like edit-group',
    );

    await tester.tap(find.text('Fast').first);
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<String>>(pace).selected, {'fast'});

    final bladderSwitch = find.descendant(
      of: find.widgetWithText(Column, 'Bladder').first,
      matching: find.byType(Switch),
    );
    expect(
      tester.widget<Switch>(bladderSwitch).onChanged,
      isNotNull,
      reason: 'create-group must wire onNeedsOffChanged like edit-group',
    );
  });
}
