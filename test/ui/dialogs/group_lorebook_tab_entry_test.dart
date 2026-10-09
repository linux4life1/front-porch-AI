// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings → Lorebook & Worlds. The dialog drew its surface as a
// coloured Container between its Material and every tab, so each ListTile
// on the tab (the inherit switch, and an entry tile once it has a colour)
// failed Flutter's "ink may be invisible" assertion. An entry was titled by
// its keywords instead of the Name typed for it. An unreadable stored book
// opened as an empty list with no word, and the next switch tap wiped it.
// The chat sidebar (real ChatService) says the book cannot be read too.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/lorebook_panel.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

class _ChatWithGroup extends FakeChatService {
  _ChatWithGroup(this._group);
  final GroupChat _group;

  @override
  GroupChat? get activeGroup => _group;
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_lore_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late GroupChatRepository repo;

  Future<void> boot(String groupLorebook) async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    repo = GroupChatRepository(storage, db);
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-duet', name: 'Porch Duet'),
    );
    for (final m in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-duet',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-duet', name: 'Porch Duet'),
      groupRepo: repo,
    );
    chat.activeGroup!.groupLorebook = groupLorebook;
  }

  // The whole dialog, as the app shows it: the assertion is about what sits
  // between a tile and the dialog's Material. The dialog reads only the
  // live group, so the settings-dialog suites' fakes carry it.
  Future<GroupChat> pumpTab(WidgetTester tester, String book) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final group = GroupChat(id: 'grp-duet', name: 'Porch Duet')
      ..groupLorebook = book;
    final fakeChat = _ChatWithGroup(group);
    final fakeRepo = FakeGroupChatRepository();
    final worlds = FakeWorldRepository();
    addTearDown(fakeChat.dispose);
    addTearDown(fakeRepo.dispose);
    addTearDown(worlds.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: fakeChat),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupSettingsDialog(
              chatService: fakeChat,
              groupRepo: fakeRepo,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final tab = find.text('Lorebook & Worlds');
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    return group;
  }

  final oakBook = jsonEncode(
    Lorebook(
      entries: [
        LorebookEntry(
          name: 'Old Oak',
          keys: ['oak', 'tree'],
          content: 'Three hundred years old; carries the rope swing.',
        ),
        LorebookEntry(keys: ['well'], content: 'The well is dry.'),
      ],
    ).toJson(),
  );

  testWidgets('an entry draws without the ink assertion, titled by its name', (
    tester,
  ) async {
    await pumpTab(tester, oakBook);

    expect(tester.takeException(), isNull);
    expect(find.text('Old Oak'), findsOneWidget);
    expect(find.text('oak, tree'), findsOneWidget, reason: 'keys as subtitle');
    // No name: the keywords stay the title.
    expect(find.text('well'), findsOneWidget);
  });

  testWidgets('an unreadable book says so and a world tap does not wipe it', (
    tester,
  ) async {
    const broken = '{"entries": [ broken';
    final group = await pumpTab(tester, broken);

    expect(tester.takeException(), isNull);
    expect(find.textContaining("lorebook couldn't be read"), findsOneWidget);

    await tester.tap(find.text('Inherit character lorebooks'));
    await tester.pump();
    expect(group.groupLorebook, broken);
  });

  testWidgets('the chat sidebar says an unreadable group book is unused', (
    tester,
  ) async {
    await tester.runAsync(() => boot('{"entries": [ broken'));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GroupLorebookSection(chatService: chat)),
      ),
    );
    await tester.pump();

    expect(find.text(kGroupLorebookUnreadableSidebarNote), findsOneWidget);
  });
}
