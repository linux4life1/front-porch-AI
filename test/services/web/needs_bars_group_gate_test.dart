// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The group twin of needs_bars_feed_gate_test.dart and
// needs_bars_follow_gate_test.dart. A group member's Needs bars show while
// Needs run and only then (Realism AND the chat's Needs switch AND Porch
// Life Needs): on the desktop member card and in the phone's member feed.
// The card gated on Realism alone and the feed on the stored switch, so a
// member kept frozen bars with Needs off (maintainer, 2026-10-08: "Needs
// bars shouldn't be visible with needs off"). A real group chat, so the
// switches are the real ones.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_bars_').path;
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

  Future<void> boot() async {
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

    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-bars',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-bars',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-bars',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    await chat.setNeedsSimEnabled(true);
  }

  ChatParticipant member() => chat.cast.firstWhere((p) => !p.isHost);

  bool feedSendsBars() {
    final snap = ChatRealismRead(chat).participantRealism(member().id)!;
    final needs = snap['needs'] as Map?;
    return needs != null && needs.isNotEmpty;
  }

  Future<bool> cardShowsBars(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: GroupMemberCard(
                character: member().card,
                chatService: chat,
                avatarColor: AppColors.formMasterAccent,
                isNextSpeaker: false,
                isExpanded: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return find.byType(NeedsGrid).evaluate().isNotEmpty;
  }

  Future<void> check(
    WidgetTester tester, {
    required bool shows,
    required String why,
  }) async {
    expect(feedSendsBars(), shows, reason: 'phone feed: $why');
    expect(await cardShowsBars(tester), shows, reason: 'member card: $why');
  }

  testWidgets('a group member: bars follow all three switches', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));

    expect(chat.isGroupMode, isTrue);
    await check(tester, shows: true, why: 'all three on');

    await tester.runAsync(
      () => storage.realismSettings.setNeedsSimDefault(false),
    );
    await check(tester, shows: false, why: 'Porch Life Needs off');
    await tester.runAsync(
      () => storage.realismSettings.setNeedsSimDefault(true),
    );
    await check(tester, shows: true, why: 'Porch Life Needs on again');

    await tester.runAsync(() => chat.setNeedsSimEnabled(false));
    expect(chat.realismEnabled, isTrue, reason: 'Realism does not need Needs');
    await check(tester, shows: false, why: "this chat's Needs off");
    await tester.runAsync(() => chat.setNeedsSimEnabled(true));

    await tester.runAsync(() => chat.setRealismEnabled(false));
    expect(chat.needsSimEnabled, isTrue);
    await check(tester, shows: false, why: 'Realism off');
  });

  testWidgets("a group member's Lust follows Porch Life, the group chat's "
      'switch and their own', (tester) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    Future<void> lust({required bool shows, required String why}) async {
      final snap = ChatRealismRead(chat).participantRealism(member().id)!;
      expect(snap['lustOn'], shows, reason: 'phone feed: $why');
      await cardShowsBars(tester);
      expect(
        find.textContaining('Lust'),
        shows ? findsWidgets : findsNothing,
        reason: 'member card: $why',
      );
    }

    await lust(shows: false, why: 'Porch Life Afterglow off');
    await tester.runAsync(() async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
    });
    await lust(shows: true, why: 'all three on');
    await tester.runAsync(
      () => chat.setMemberAfterglowEnabled(member().card, false),
    );
    await lust(shows: false, why: "this member's own switch off");
    await tester.runAsync(
      () => chat.setMemberAfterglowEnabled(member().card, true),
    );
    await tester.runAsync(() => chat.setAfterglowEnabled(false));
    await lust(shows: false, why: "the group chat's switch off");
  });

  test("the phone's member switch flips that member's own Afterglow", () async {
    await boot();
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final facade = ChatToolsFacade(chat, storage, null);
    final router = shelf_router.Router();
    WebChatToolsRoutes(facade, router);
    final card = member().card;
    final id = groupMemberStoreId(card);
    List<dynamic> members() =>
        (facade.state()['nsfw'] as Map)['members'] as List<dynamic>;
    Object? runsWhenFocused() =>
        (facade.state(participantId: member().id)['nsfw']
            as Map)['cooldownEnabled'];
    expect(members().map((m) => (m as Map)['afterglow']), everyElement(true));
    expect(runsWhenFocused(), isTrue);

    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/tools/toggle'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'name': 'memberAfterglow', 'id': id, 'value': false}),
      ),
    );
    expect(res.statusCode, 200);
    expect(chat.afterglowRunsFor(card), isFalse);
    expect(
      members().firstWhere((m) => (m as Map)['id'] == id)['afterglow'],
      isFalse,
    );
    expect(
      runsWhenFocused(),
      isFalse,
      reason: 'focused on the member, the phone reads their own switch',
    );
  });

  test("the phone's Group Settings carries each member's Recovery while "
      'Afterglow runs for them, and saves it to them', () async {
    await boot();
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final facade = ChatToolsFacade(chat, storage, null);
    final router = shelf_router.Router();
    WebChatToolsRoutes(facade, router);
    final card = member().card;
    final id = groupMemberStoreId(card);
    Map<dynamic, dynamic> row() =>
        ((facade.state()['group'] as Map)['members'] as List)
            .cast<Map<dynamic, dynamic>>()
            .firstWhere((m) => m['id'] == id);
    expect(row()['afterglowRuns'], isTrue);

    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/tools/member-recovery'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'id': id,
          'recovery': {'recoveryMode': 'hard', 'recoveryMinutes': 45},
        }),
      ),
    );
    expect(res.statusCode, 200);
    expect(card.frontPorchExtensions?.recovery.recoveryMinutes, 45);
    expect((row()['recovery'] as Map)['recoveryMinutes'], 45);

    await chat.setMemberAfterglowEnabled(card, false);
    expect(row()['afterglowRuns'], isFalse);
  });
}
