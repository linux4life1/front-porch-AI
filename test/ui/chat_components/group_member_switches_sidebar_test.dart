// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// PR 3 of docs/design/one-chat-ux.md: in a group, the Realism, Needs,
// Afterglow and Pockets switches in Character State drive the TAPPED member
// alone, for this chat. A real group chat and the real ChatRightSidebar.
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
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/pockets_gate_line.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../helpers/chat_db_teardown.dart';

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
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await storage.realismSettings.setPocketsEnabled(true);
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

  Future<void> tapChip(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(CastRosterChip, name));
    await settle(tester);
  }

  Finder row(String label) => find.byWidgetPredicate(
    (w) => w is RealismProgressRow && w.label == label,
  );

  Finder switchIn(Finder anchor) => find
      .descendant(
        of: find.ancestor(of: anchor, matching: find.byType(Row)).first,
        matching: find.byType(Switch),
      )
      .first;

  Finder headerSwitch() => find
      .descendant(
        of: find
            .ancestor(
              of: find.text('Character State'),
              matching: find.byType(PorchAccordion),
            )
            .first,
        matching: find.byType(Switch),
      )
      .first;

  Future<void> flip(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  String id(String name) => chat.characterIdFor(
    chat.groupCharacters.firstWhere((c) => c.name == name),
  );

  testWidgets('the header Realism switch flips only the tapped member', (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    await tapChip(tester, 'Bea');
    expect(tester.widget<Switch>(headerSwitch()).value, isTrue);

    await flip(tester, headerSwitch());
    expect(chat.realismSwitchFor(id('Bea')), isFalse);
    expect(chat.realismSwitchFor(id('Ana')), isTrue, reason: 'only Bea');
    expect(tester.widget<Switch>(headerSwitch()).value, isFalse);
    expect(find.textContaining('off for Bea'), findsOneWidget);
    expect(row('Short-Term Bond'), findsNothing);

    await tapChip(tester, 'Ana');
    expect(tester.widget<Switch>(headerSwitch()).value, isTrue);
    expect(row('Short-Term Bond'), findsOneWidget);
  });

  testWidgets('the Needs line switch drives the tapped member alone', (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    await tapChip(tester, 'Bea');
    await flip(tester, switchIn(find.text('Needs')));
    expect(chat.needsSwitchFor(id('Bea')), isFalse);
    expect(chat.needsSwitchFor(id('Ana')), isTrue);
    expect(find.byType(NeedsGrid), findsNothing, reason: 'Bea\'s bars hold');

    await tapChip(tester, 'Ana');
    expect(find.byType(NeedsGrid), findsOneWidget);
  });

  testWidgets('the Afterglow line shows in a group and drives the tapped '
      'member alone', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    await tapChip(tester, 'Bea');
    expect(find.text('Afterglow'), findsOneWidget);
    expect(row('Lust'), findsOneWidget, reason: 'Lust under it');

    await flip(tester, switchIn(find.text('Afterglow')));
    expect(chat.afterglowSwitchFor(id('Bea')), isFalse);
    expect(chat.afterglowSwitchFor(id('Ana')), isTrue);
    expect(row('Lust'), findsNothing);
    await tapChip(tester, 'Ana');
    expect(row('Lust'), findsOneWidget);
  });

  testWidgets('the Pockets line drives the tapped member alone', (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await pumpSidebar(tester);
    await tapChip(tester, 'Bea');
    final pockets = find.descendant(
      of: find.byType(PocketsGateLine),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(pockets);
    await tester.tap(pockets);
    await settle(tester);
    await tester.tap(find.text('Yes, turn off'));
    await settle(tester);
    expect(chat.pocketsSwitchFor(id('Bea')), isFalse);
    expect(chat.pocketsSwitchFor(id('Ana')), isTrue);
  });
}
