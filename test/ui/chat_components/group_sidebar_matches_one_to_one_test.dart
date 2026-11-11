// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// PR 2 of docs/design/one-chat-ux.md: the group sidebar is the 1:1 sidebar
// for the tapped cast member. A real group chat (the switches and per-member
// entries are the real ones), the real ChatRightSidebar, and a tap on a cast
// chip.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/group_dynamics_section.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/memory_off_everywhere_note.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/memory_panel.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/memory_sources_list.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/story_tools.dart'
    show AfkPanel, GroupObjectivesPanel;
import 'package:front_porch_ai/ui/pages/chat_page.call_button.dart';
import 'package:front_porch_ai/ui/pages/chat_page.main_settings_items.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar.dart';
import 'package:front_porch_ai/ui/pages/chat_page_sidebar_host.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show RelationshipTiers;
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../golden/support/fakes.dart' show FakeSttService;
import '../../helpers/chat_db_teardown.dart';

class _QuietEmbeddings extends EmbeddingService {
  _QuietEmbeddings(super.storage);

  @override
  bool get isAvailable => true;

  @override
  Future<void> ensureReady() async {}
}

class _Library extends CharacterRepository {
  _Library(super.db, super.storage, this.cards);

  final List<CharacterCard> cards;

  @override
  List<CharacterCard> get characters => cards;
}

class _Stt extends FakeSttService {
  @override
  bool get isBusy => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_side_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  /// Ana and Bea differ on every value the leaves show, so a leaf that read
  /// the wrong member (or the chat's live scalars) shows the wrong number.
  Future<void> boot({int members = 2}) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
    });
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

    final names = ['Ana', 'Bea', 'Cy', 'Dot', 'Eve'].take(members).toList();
    final ids = [for (final n in names) 'mem-${n.toLowerCase()}'];
    Map<String, dynamic> seed(int i) {
      final s = defaultGroupMemberRealismSeed();
      s['affection'] = i == 0 ? 35 : 120;
      s['trust'] = i == 0 ? 40 : -60;
      s['fixation'] = i == 0 ? '' : 'her missing sister';
      s['fixationLifespan'] = 3;
      (s['needs'] as Map<String, int>)['hunger'] = i == 0 ? 75 : 12;
      // Ana's feelings toward the others are warm; Bea's are cold.
      s['relationships'] = <String, int>{
        for (var j = 0; j < ids.length; j++)
          if (j != i) ids[j]: i == 0 ? 150 : -90,
      };
      return s;
    }

    final blobs = buildGroupRealismBlobs(
      seeds: {for (var i = 0; i < ids.length; i++) ids[i]: seed(i)},
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-side',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (var i = 0; i < ids.length; i++) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: ids[i],
          groupId: 'grp-side',
          name: names[i],
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-side',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    await chat.setNeedsSimEnabled(true);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  Future<void> pumpSidebar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? focusedId;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<WorldRepository>.value(
            value: WorldRepository(storage, db),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ChatRightSidebar(
                chatService: chat,
                focusedParticipantId: focusedId,
                onFocusParticipant: (id) => setState(() => focusedId = id),
                sidebarWidth: 360,
                resolveCharImage: File.new,
                draft: TextEditingController(),
                onJumpToMessage: (_) {},
                onEditCharacter:
                    (card, {ensureRelationshipVisible = false}) async {},
                onAvatarsChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  RealismProgressRow bar(WidgetTester tester, String label) =>
      tester.widget<RealismProgressRow>(
        find.byWidgetPredicate(
          (w) => w is RealismProgressRow && w.label == label,
        ),
      );

  Future<void> tapChip(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(CastRosterChip, name));
    await settle(tester);
  }

  Finder dynamicsRow(String name) => find.byWidgetPredicate(
    (w) =>
        w is RealismProgressRow &&
        w.key.toString().contains('group-dynamics') &&
        w.label == name,
  );

  testWidgets('tapping a cast chip swaps Character State to that member', (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);

    // The same leaves a 1:1 shows, for the first member.
    expect(bar(tester, 'Short-Term Bond').value, 35);
    expect(bar(tester, 'Trust').value, 40);
    expect(find.byType(FixationChip), findsNothing);
    expect(
      tester.widget<NeedsGrid>(find.byType(NeedsGrid)).needs['hunger'],
      75,
    );
    // Member cards are gone from Character State.
    expect(find.byType(GroupMemberCard), findsNothing);

    await tapChip(tester, 'Bea');
    expect(bar(tester, 'Short-Term Bond').value, 120);
    expect(bar(tester, 'Trust').value, -60);
    expect(find.byType(FixationChip), findsOneWidget);
    expect(
      tester.widget<FixationChip>(find.byType(FixationChip)).topic,
      'her missing sister',
    );
    expect(
      tester.widget<NeedsGrid>(find.byType(NeedsGrid)).needs['hunger'],
      12,
    );

    await tapChip(tester, 'Ana');
    expect(bar(tester, 'Short-Term Bond').value, 35);
  });

  testWidgets('Group Dynamics lists the other members, read-only', (
    tester,
  ) async {
    await tester.runAsync(() => boot(members: 3));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);

    expect(find.text('Group Dynamics'), findsOneWidget);
    // Ana toward Bea and Cy (150 each), not toward herself.
    expect(dynamicsRow('Bea'), findsOneWidget);
    expect(dynamicsRow('Cy'), findsOneWidget);
    expect(dynamicsRow('Ana'), findsNothing);
    expect(tester.widget<RealismProgressRow>(dynamicsRow('Bea')).value, 150);

    await tapChip(tester, 'Bea');
    expect(dynamicsRow('Ana'), findsOneWidget);
    expect(dynamicsRow('Bea'), findsNothing);
    expect(tester.widget<RealismProgressRow>(dynamicsRow('Ana')).value, -90);
    // Nothing in it is a control.
    expect(
      find.descendant(
        of: find.byType(GroupDynamicsSection),
        matching: find.byType(Switch),
      ),
      findsNothing,
    );
  });

  testWidgets('five members: Group Dynamics says it is not tracked', (
    tester,
  ) async {
    await tester.runAsync(() => boot(members: 5));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    expect(find.text('Group Dynamics'), findsOneWidget);
    expect(find.textContaining('groups of two to four'), findsOneWidget);
    expect(dynamicsRow('Bea'), findsNothing);
  });

  testWidgets('Objectives and the AFK leaf show in a group, for the member', (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    expect(chat.objectivesActive, isTrue);

    expect(find.text('Objectives'), findsOneWidget);
    await tester.tap(find.text('Objectives'));
    await settle(tester);
    expect(find.byType(GroupObjectivesPanel), findsOneWidget);
    // The panel reads the member's goals from the database before it paints.
    Future<void> loaded(String text) async {
      for (var i = 0; i < 40; i++) {
        if (find.textContaining(text).evaluate().isNotEmpty) return;
        await settle(tester);
      }
    }

    await loaded("Ana's primary objective");
    expect(find.textContaining("Ana's primary objective"), findsOneWidget);
    await tapChip(tester, 'Bea');
    await loaded("Bea's primary objective");
    expect(find.textContaining("Bea's primary objective"), findsOneWidget);
    expect(find.textContaining("Ana's primary objective"), findsNothing);

    await tester.tap(find.text('Story Tools'));
    await tester.pump();
    expect(find.byType(AfkPanel), findsOneWidget);
  });

  testWidgets(
    'Group Settings… is in Main Settings; the pinned button is gone',
    (tester) async {
      await tester.runAsync(boot);
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await pumpSidebar(tester);

      expect(
        find.widgetWithText(OutlinedButton, 'Group Settings'),
        findsNothing,
      );
      await tester.tap(find.text('Main Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Group Settings…'), findsOneWidget);
    },
  );

  test('only a group\'s Main Settings has Group Settings…', () {
    List<String?> values({required bool isGroup}) => [
      for (final e in mainSettingsItems(isGroup: isGroup))
        if (e is PopupMenuItem<String>) e.value,
    ];
    expect(values(isGroup: false), isNot(contains('group_settings')));
    expect(values(isGroup: true), contains('group_settings'));
  });

  testWidgets('voice call: greyed with "1:1 only" in a group', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.runAsync(() => storage.sttSettings.setSttEnabled(true));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<SttService>.value(value: _Stt()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatCallButton(chatService: chat, onStartCall: () {}),
          ),
        ),
      ),
    );
    expect(chat.isGroupMode, isTrue);
    expect(find.byTooltip('1:1 only'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });

  testWidgets('Group Dynamics rows read like the bond bars: the next-tier '
      'target is the denominator', (tester) async {
    await tester.runAsync(() => boot(members: 3));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);

    // Ana toward Bea is 150; the bar fills within its tier, so the number
    // beside it is that tier's target, never the +/-300 ceiling.
    final row = tester.widget<RealismProgressRow>(dynamicsRow('Bea'));
    expect(row.value, 150);
    expect(row.maxValue, RelationshipTiers.bondScaleTarget(150));
    expect(row.maxValue, isNot(300));
  });

  testWidgets('the group header names the turn order in words', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: ChatPageAppBar(
              chatService: chat,
              coverFor: (_, _) => null,
              sidebarOpen: false,
              onToggleSidebar: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('2 characters • Round Robin'), findsOneWidget);
    expect(find.textContaining('roundRobin'), findsNothing);
  });

  testWidgets('the Memory leaf shows in a group for the tapped member, and its '
      'switch is the group\'s own', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.runAsync(() => storage.memorySettings.setRagEnabled(true));
    tester.view.physicalSize = const Size(900, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? focusedId;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<WorldRepository>.value(
            value: WorldRepository(storage, db),
          ),
          ChangeNotifierProvider<EmbeddingService>.value(
            value: _QuietEmbeddings(storage),
          ),
          ChangeNotifierProvider<CharacterRepository>.value(
            value: CharacterRepository(db, storage),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ChatRightSidebar(
                chatService: chat,
                focusedParticipantId: focusedId,
                onFocusParticipant: (id) => setState(() => focusedId = id),
                sidebarWidth: 360,
                resolveCharImage: File.new,
                draft: TextEditingController(),
                onJumpToMessage: (_) {},
                onEditCharacter:
                    (card, {ensureRelationshipVisible = false}) async {},
                onAvatarsChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.textContaining('Journal & Memory'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MemoryPanel), findsOneWidget);
    expect(
      tester.widget<MemoryPanel>(find.byType(MemoryPanel)).member?.name,
      'Ana',
    );
    await tapChip(tester, 'Bea');
    expect(
      tester.widget<MemoryPanel>(find.byType(MemoryPanel)).member?.name,
      'Bea',
    );

    // The group's gate is on by default: the leaf shows the group's, and
    // flipping it leaves the global setting alone.
    Finder memorySwitch() => find.descendant(
      of: find.byType(MemoryPanel),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(memorySwitch()).value, isTrue);
    await tester.ensureVisible(memorySwitch());
    await tester.pump();
    await tester.tap(memorySwitch());
    await settle(tester);
    expect(chat.groupRagEnabled, isFalse);
    expect(storage.memorySettings.ragEnabled, isTrue);
    expect(tester.widget<Switch>(memorySwitch()).value, isFalse);

    // With the global setting off, the group's switch is unavailable (its
    // choice kept) and says why.
    await tester.runAsync(() => storage.memorySettings.setRagEnabled(false));
    await settle(tester);
    expect(tester.widget<Switch>(memorySwitch()).onChanged, isNull);
    expect(find.text(MemoryOffEverywhereNote.text), findsOneWidget);
  });

  testWidgets('the Sources picker lists the other members of a group', (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.runAsync(() => storage.memorySettings.setRagEnabled(true));
    tester.view.physicalSize = const Size(900, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The library holds the cast: a member's memory id is its library id.
    final library = _Library(db, storage, [
      CharacterCard(name: 'Ana', imagePath: '/lib/mem-ana.png'),
      CharacterCard(name: 'Bea', imagePath: '/lib/mem-bea.png'),
      CharacterCard(name: 'Zoe', imagePath: '/lib/zoe.png'),
    ]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<WorldRepository>.value(
            value: WorldRepository(storage, db),
          ),
          ChangeNotifierProvider<EmbeddingService>.value(
            value: _QuietEmbeddings(storage),
          ),
          ChangeNotifierProvider<CharacterRepository>.value(value: library),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatRightSidebar(
              chatService: chat,
              focusedParticipantId: null,
              onFocusParticipant: (_) {},
              sidebarWidth: 360,
              resolveCharImage: File.new,
              draft: TextEditingController(),
              onJumpToMessage: (_) {},
              onEditCharacter:
                  (card, {ensureRelationshipVisible = false}) async {},
              onAvatarsChanged: () {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.textContaining('Journal & Memory'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Sources'));
    await tester.tap(find.text('Sources'));
    await settle(tester);
    final list = find.byType(MemorySourcesList);
    expect(
      find.descendant(of: list, matching: find.text('Bea')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.text('Zoe')),
      findsOneWidget,
    );
    expect(find.descendant(of: list, matching: find.text('Ana')), findsNothing);
  });
}
