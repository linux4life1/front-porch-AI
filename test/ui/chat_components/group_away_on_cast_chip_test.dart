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
// (member Realism on, or the clock running), and the user's Away / Back for
// a member lives on that member's cast chip, not on the presence word.

/// The real chat with the turn-busy read pinned, since a real turn cannot be
/// held open in a widget test.
class _BusyChat extends ChatService {
  _BusyChat(super.kobold, super.persona, super.storage, super.worlds);

  bool busy = false;

  @override
  bool get isTurnBusy => busy;
}

Widget _chip({
  required PresenceWhere? presence,
  ValueChanged<bool>? onSetAway,
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

  Finder awayButton(String member) => find.descendant(
    of: find.widgetWithText(CastRosterChip, member),
    matching: find.byKey(const ValueKey('cast-chip-away')),
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

  testWidgets('the cast chip Away / Back marks a member away and back', (
    tester,
  ) async {
    await tester.runAsync(() => boot(clockRunning: false));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);

    expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.withYou);
    expect(
      find.descendant(of: awayButton('Ana'), matching: find.text('Away')),
      findsOneWidget,
    );

    await tester.tap(awayButton('Ana'));
    await settle(tester);
    expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.away);
    expect(chat.groupMemberPresence('mem-bea'), PresenceWhere.withYou);
    expect(
      find.descendant(of: awayButton('Ana'), matching: find.text('Back')),
      findsOneWidget,
    );

    await tester.tap(awayButton('Ana'));
    await settle(tester);
    expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.withYou);
  });

  testWidgets('the cast chip Away control is off while a turn is busy', (
    tester,
  ) async {
    await tester.runAsync(() => boot(clockRunning: false));
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    chat.busy = true;
    await pumpSidebar(tester);

    final button = tester.widget<TextButton>(awayButton('Ana'));
    expect(button.onPressed, isNull);
    await tester.tap(awayButton('Ana'), warnIfMissed: false);
    await settle(tester);
    expect(chat.groupMemberPresence('mem-ana'), PresenceWhere.withYou);
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

  testWidgets('chip control: Away from With you, Back from Away, none else', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _chip(presence: PresenceWhere.withYou, onSetAway: calls.add),
    );
    await tester.tap(find.text('Away'));
    await tester.pumpWidget(
      _chip(presence: PresenceWhere.away, onSetAway: calls.add),
    );
    await tester.tap(find.text('Back'));
    expect(calls, [true, false]);

    for (final hidden in [
      _chip(presence: PresenceWhere.atWork, onSetAway: calls.add),
      _chip(presence: null, onSetAway: calls.add),
      _chip(
        presence: PresenceWhere.withYou,
        onSetAway: calls.add,
        isLite: true,
      ),
    ]) {
      await tester.pumpWidget(hidden);
      expect(find.byKey(const ValueKey('cast-chip-away')), findsNothing);
    }

    await tester.pumpWidget(_chip(presence: PresenceWhere.withYou));
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('cast-chip-away')))
          .onPressed,
      isNull,
    );
  });
}
