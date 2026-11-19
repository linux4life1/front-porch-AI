// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

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
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_leaves.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../helpers/chat_db_teardown.dart';

// One UI: a group's Character State shows the time leaf by the 1:1 rule
// (member Realism on, or the clock running). The cast chip wears an honest
// presence word (status only); the Away / Back action lives in the chip's
// right-click / hold menu, and the Next pill queues the speaker.

class _BusyChat extends ChatService {
  _BusyChat(super.kobold, super.persona, super.storage, super.worlds);

  bool busy = false;

  @override
  bool get isTurnBusy => busy;
}

Widget _chip({
  required PresenceWhere? presence,
  ValueChanged<bool>? onSetAway,
  VoidCallback? onQueue,
  bool isLite = false,
}) => MaterialApp(
  home: Scaffold(
    body: CastRosterChip(
      name: 'Ana',
      color: Colors.teal,
      isFocused: false,
      isLite: isLite,
      onFocus: () {},
      presence: presence,
      onSetAway: onSetAway,
      onQueue: onQueue,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_away_chip_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late _BusyChat chat;

  Future<void> boot({required bool clockRunning}) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': clockRunning,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        _BusyChat(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    const ids = ['mem-ana', 'mem-bea'];
    final blobs = buildGroupRealismBlobs(
      seeds: {for (final id in ids) id: defaultGroupMemberRealismSeed()},
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-away',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final entry in {'mem-ana': 'Ana', 'mem-bea': 'Bea'}.entries) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: entry.key,
          groupId: 'grp-away',
          name: entry.value,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-away',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
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

  Finder chip(String member) => find.widgetWithText(CastRosterChip, member);

  Future<void> openMenu(WidgetTester tester, String member) async {
    await tester.longPress(chip(member));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the chip wears the honest status word; the menu sends away and brings '
    'back',
    (tester) async {
      await tester.runAsync(() => boot(clockRunning: false));
      addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
      await pumpSidebar(tester);

      expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.withYou);
      // Status word on the chip says what is true, not what the tap does.
      expect(
        find.descendant(of: chip('Ana'), matching: find.text('With you')),
        findsOneWidget,
      );

      await openMenu(tester, 'Ana');
      await tester.tap(find.text('Send away'));
      await settle(tester);
      expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.away);
      expect(
        find.descendant(of: chip('Ana'), matching: find.text('Away')),
        findsOneWidget,
      );

      await openMenu(tester, 'Ana');
      await tester.tap(find.text('Bring back'));
      await settle(tester);
      expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.withYou);
    },
  );

  testWidgets(
    'while a turn is busy: no away row in the menu (service refuses), but '
    'Next still queues (it fires nothing)',
    (tester) async {
      await tester.runAsync(() => boot(clockRunning: false));
      addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
      chat.busy = true;
      await pumpSidebar(tester);

      await openMenu(tester, 'Ana');
      expect(find.text('Send away'), findsNothing);
      expect(find.text('Queue to speak next'), findsOneWidget);
      await tester.tap(find.text('Queue to speak next'));
      await settle(tester);
      expect(chat.queuedSpeaker?.name, 'Ana');
    },
  );

  testWidgets(
    'group, member Realism off, clock paused: no time leaf (as 1:1)',
    (tester) async {
      await tester.runAsync(() => boot(clockRunning: false));
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.runAsync(
        () => chat.setMemberRealismEnabled('mem-ana', false),
      );
      await pumpSidebar(tester);

      // Ana is focused first: Realism off, clock paused.
      expect(chat.realismSwitchFor('mem-ana'), isFalse);
      expect(find.byType(TimeLeaf), findsNothing);

      // Bea has Realism on: the same group shows the leaf for her.
      await tester.tap(find.widgetWithText(CastRosterChip, 'Bea'));
      await settle(tester);
      expect(find.byType(TimeLeaf), findsOneWidget);
    },
  );

  testWidgets('group, member Realism off, clock running: time leaf shows', (
    tester,
  ) async {
    await tester.runAsync(() => boot(clockRunning: true));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.runAsync(() => chat.setMemberRealismEnabled('mem-ana', false));
    await pumpSidebar(tester);
    expect(find.byType(TimeLeaf), findsOneWidget);
  });

  testWidgets('the Next pill queues from the chip and cancels on a re-tap', (
    tester,
  ) async {
    await tester.runAsync(() => boot(clockRunning: false));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);

    await tester.tap(find.descendant(of: chip('Ana'), matching: find.text('Next')));
    await settle(tester);
    expect(chat.queuedSpeaker?.name, 'Ana');

    // The pill flipped to the NEXT read; tapping it cancels the hold.
    await tester.tap(find.descendant(of: chip('Ana'), matching: find.text('NEXT')));
    await settle(tester);
    expect(chat.queuedSpeaker, isNull);
  });

  testWidgets('the presence word is read-only (no toggle on the time leaf)', (
    tester,
  ) async {
    await tester.runAsync(() => boot(clockRunning: true));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    expect(find.text('With you'), findsWidgets);
    expect(find.byKey(const ValueKey('presence-toggle')), findsNothing);
  });

  testWidgets('chip words: every presence reads, At work never offers a '
      'toggle, lite and host show no word',
    (tester) async {
      var menuAwayCalls = 0;
      await tester.pumpWidget(
        _chip(
          presence: PresenceWhere.withYou,
          onSetAway: (_) => menuAwayCalls++,
          onQueue: () {},
        ),
      );
      expect(find.text('With you'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      await tester.pumpWidget(
        _chip(
          presence: PresenceWhere.away,
          onSetAway: (_) => menuAwayCalls++,
          onQueue: () {},
        ),
      );
      expect(find.text('Away'), findsOneWidget);

      // At work: the word shows (truth) but the menu offers no toggle —
      // the clock owns that state.
      await tester.pumpWidget(
        _chip(
          presence: PresenceWhere.atWork,
          onSetAway: (_) => menuAwayCalls++,
          onQueue: () {},
        ),
      );
      await openMenu(tester, 'Ana');
      expect(find.text('Send away'), findsNothing);
      expect(find.text('Bring back'), findsNothing);

      // Lite guests and host-side chips (no presence) carry no word.
      for (final hidden in [
        _chip(
          presence: PresenceWhere.withYou,
          onSetAway: (_) => menuAwayCalls++,
          isLite: true,
        ),
        _chip(presence: null, onSetAway: (_) => menuAwayCalls++),
      ]) {
        await tester.pumpWidget(hidden);
        expect(find.text('With you'), findsNothing);
      }
    },
  );
}
