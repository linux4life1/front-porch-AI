// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit Character, Create Character and Create Group used to drop hours of
// typing on back without a word. Each now asks when it holds unsaved work,
// leaves quietly when it holds none, and Save still leaves without asking.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_character_page.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

const _question = 'Discard unsaved changes?';

class _NoCoverRepo extends FakeCharacterRepository {
  _NoCoverRepo() : super([]);
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Pumps [providers] around a home with an Open button that pushes [page].
Future<void> _pushed(
  WidgetTester tester,
  List<ChangeNotifierProvider> providers,
  Widget Function() page,
) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: providers,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => page())),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await _settle(tester);
}

Future<void> _answer(WidgetTester tester, {required bool discard}) async {
  expect(find.text(_question), findsOneWidget);
  await tester.tap(
    discard
        ? find.byKey(const ValueKey('unsaved-discard'))
        : find.text('Keep editing'),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Edit Character', () {
    Future<void> open(WidgetTester tester) async {
      final repo = _NoCoverRepo();
      final chat = FakeChatService();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      for (final s in [repo, chat, storage, worlds]) {
        addTearDown(s.dispose);
      }
      await _pushed(
        tester,
        [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        () => EditCharacterPage(
          character: CharacterCard(name: 'Ada', description: 'On the porch.'),
          onSaveOverride: (_) async {},
        ),
      );
      expect(find.text('Edit Ada'), findsOneWidget);
    }

    testWidgets('back from an untouched card leaves without asking', (
      tester,
    ) async {
      await open(tester);
      await _back(tester);
      expect(find.text(_question), findsNothing);
      expect(find.text('Edit Ada'), findsNothing);
    });

    testWidgets('an edited description asks; Save leaves without asking', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'On the porch.'),
        'Hours of backstory',
      );
      await tester.pump();

      await _back(tester);
      await _answer(tester, discard: false);
      expect(find.text('Edit Ada'), findsOneWidget);
      expect(find.text('Hours of backstory'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text(_question), findsNothing);
      expect(find.text('Edit Ada'), findsNothing);
    });
  });

  group('Create Character', () {
    Future<AppState> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appState = AppState()..setIndex(1);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: const MaterialApp(home: CreateCharacterPage()),
        ),
      );
      await _settle(tester);
      return appState;
    }

    testWidgets('back from a blank wizard goes Home without asking', (
      tester,
    ) async {
      final appState = await open(tester);
      await _back(tester);
      expect(find.text(_question), findsNothing);
      expect(appState.selectedIndex, 0);
    });

    testWidgets('back from a named character asks before going Home', (
      tester,
    ) async {
      final appState = await open(tester);
      await tester.enterText(find.byType(TextField).first, 'Juniper');
      await tester.pump();

      await _back(tester);
      await _answer(tester, discard: false);
      expect(appState.selectedIndex, 1);
      expect(find.text('Juniper'), findsOneWidget);

      await _back(tester);
      await _answer(tester, discard: true);
      expect(appState.selectedIndex, 0);
    });
  });

  group('Create Group', () {
    Future<void> open(WidgetTester tester) async {
      final cast = [
        for (final n in ['Juniper', 'Marlow'])
          CharacterCard(name: n, description: '$n is here.'),
      ];
      final repo = FakeCharacterRepository(cast);
      final chat = FakeChatService();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      final folders = FakeFolderService();
      final groups = FakeGroupChatRepository();
      final llm = FakeLLMProvider();
      final tts = FakeTtsService();
      for (final s in [repo, chat, storage, worlds, folders, groups, llm]) {
        addTearDown(s.dispose);
      }
      addTearDown(tts.dispose);
      await _pushed(tester, [
        ChangeNotifierProvider<CharacterRepository>.value(value: repo),
        ChangeNotifierProvider<ChatService>.value(value: chat),
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ChangeNotifierProvider<FolderService>.value(value: folders),
        ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
        ChangeNotifierProvider<LLMProvider>.value(value: llm),
        ChangeNotifierProvider<TtsService>.value(value: tts),
      ], () => const CreateGroupChatPage());
      expect(find.text('Create Group Chat'), findsOneWidget);
    }

    testWidgets('back from an empty wizard leaves without asking', (
      tester,
    ) async {
      await open(tester);
      await _back(tester);
      expect(find.text(_question), findsNothing);
      expect(find.text('Create Group Chat'), findsNothing);
    });

    testWidgets('a picked member asks before back drops the roster', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Juniper').first);
      await _settle(tester);

      await _back(tester);
      await _answer(tester, discard: false);
      expect(find.text('Create Group Chat'), findsOneWidget);

      await _back(tester);
      await _answer(tester, discard: true);
      expect(find.text('Create Group Chat'), findsNothing);
    });
  });
}
