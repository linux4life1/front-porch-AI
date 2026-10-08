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
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
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
}
