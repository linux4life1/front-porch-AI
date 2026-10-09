// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Creating a group right after Backups > Restore threw "connection was
// closed" and the group never saved. A restore closes the database the app
// opened at startup and opens the restored file in its place; every service is
// re-pointed (reopenAndRebindDatabase), but `Provider<AppDatabase>` keeps the
// startup database forever, and the wizard wrote its member rows through it.
//
// This walks the real wizard over exactly that state: the provided database
// is closed, the live one is a different, open database, and the group
// repository has been re-pointed at the live one the way a restore leaves it.
// Then Create runs the real save path, and both the group and its members
// must land in the live database.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Group avatars go to a temp folder; the library itself is never touched.
class _Storage extends FakeStorageService {
  _Storage(this.root);

  final Directory root;

  @override
  Future<void> get initialized async {}

  @override
  Directory get groupsDir => Directory('${root.path}/groups');
}

/// The real repository (its member-portrait copy runs for real), re-pointed at
/// the live database the way a restore leaves it. Only the library listing is
/// seeded, so the picker has two cards to tap without a library on disk.
class _Library extends CharacterRepository {
  _Library(super.db, super.storage, this.cards);

  final List<CharacterCard> cards;

  @override
  List<CharacterCard> get characters => cards;

  @override
  Future<void> loadCharacters() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    docsDir = Directory.systemTemp.createTempSync('fpai_group_restore_');
    // A stable documents folder, so AppDatabase.instance() opens one file.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? docsDir.path
              : null,
        );
  });

  tearDown(() {
    try {
      docsDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('after a restore, Create Group writes the group and its members '
      'to the restored database', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 950));
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

    // What Provider<AppDatabase> captured at startup; the restore closed it.
    final startup = AppDatabase.forTesting(sameIsolate: true);
    final storage = _Storage(docsDir);
    late AppDatabase live;
    late GroupChatRepository groups;
    late CharacterRepository repo;
    // Real cross-isolate I/O must run outside the fake-async zone.
    await tester.runAsync(() async {
      // Opened, as it is in the app, so the close really ends it (a database
      // closed before its first query quietly reopens on the next one).
      await startup.customSelect('SELECT 1').get();
      await startup.close();
      live = await AppDatabase.instance();
      groups = GroupChatRepository(storage, live);
      await groups.reload();
      repo = _Library(live, storage, [aerin, bo]);
    });
    addTearDown(() => tester.runAsync(AppDatabase.closeAndReset));
    expect(identical(AppDatabase.current, live), isTrue);

    final chat = FakeChatService();
    final worlds = FakeWorldRepository();
    final folders = FakeFolderService();
    final llm = FakeLLMProvider();
    final tts = FakeTtsService();
    for (final s in [repo, chat, storage, worlds, folders, llm, tts, groups]) {
      addTearDown(s.dispose);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: startup),
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
    await tester.enterText(find.byType(TextField).first, 'Restored Porch');
    await tester.pumpAndSettle();
    await next('Group System Prompt');
    await next('Add Entry');
    await next('Day Number');
    await next(
      'Pre-seed how the characters feel toward each other. These hidden '
      'relationships influence behavior in small groups (4 or fewer members).',
    );
    await next('Opening Scene');
    await next('Create Group & Enter Chat');

    const createOnly = "Create Only (don't enter chat yet)";
    await tester.ensureVisible(find.text(createOnly));
    await tester.tap(find.text(createOnly));
    // The save crosses to the database isolate: let real time pass, then pump
    // so the wizard's awaits resume, until the group lands or time runs out.
    for (var i = 0; i < 100 && groups.groups.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(
      groups.groups.map((g) => g.name),
      ['Restored Porch'],
      reason:
          'the group never saved: the wizard wrote through the database '
          'the restore had closed',
    );
    final members = await tester.runAsync(
      () => live.getGroupMembers(groups.groups.single.id),
    );
    expect(members!.map((m) => m.name).toList()..sort(), [
      'Aerin',
      'Bo',
    ], reason: 'the member rows must land in the restored database');
  });
}
