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
import 'package:front_porch_ai/services/chat/chat.dart'
    show Refractory, resolveGroupSpeakerForMessage;
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/util/image_thumbnails.dart'
    show ThumbnailCache;
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state.dart'
    show AmbitionsRow, PocketsRow;
import 'package:front_porch_ai/models/avatar_image.dart' as face;
import 'package:front_porch_ai/ui/pages/chat_page.sidebar_widgets.dart'
    show ChatSidebarPortrait;
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
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

  // Off hides a member's Lust and recovery and keeps them (zeroing them was
  // a bug): their card, the phone's member block and its chat tools show
  // neither while their switch is off, and both where they were once it is
  // back on.
  testWidgets("a member's Afterglow off hides their Lust and recovery on the "
      "card and in the phone's feeds; on shows them where they were", (
    tester,
  ) async {
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    await tester.runAsync(() async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
    });
    final card = member().card;
    final id = chat.characterIdFor(card);
    chat.debugSeedGroupSpeakerState(
      id,
      arousal: 60,
      refractory: Refractory.fromMinutes(30),
    );
    final chip = chat.getRefractoryForGroupCharacter(card).chip;
    expect(chip, isNotEmpty);
    Map<String, dynamic> block() =>
        ChatRealismRead(chat).participantRealism(member().id)!;
    Map<dynamic, dynamic> tools() =>
        ChatToolsFacade(
              chat,
              storage,
              null,
            ).state(participantId: member().id)['nsfw']
            as Map;

    await cardShowsBars(tester);
    expect(find.text('Lust: Intense'), findsOneWidget);
    expect(find.text(chip), findsOneWidget);

    await tester.runAsync(() => chat.setMemberAfterglowEnabled(card, false));
    await cardShowsBars(tester);
    expect(find.textContaining('Lust:'), findsNothing, reason: 'member card');
    expect(find.text(chip), findsNothing);
    expect(block()['lustOn'], isFalse);
    expect((block()['arousal'] as Map)['level'], 0, reason: 'member block');
    expect(block()['refractoryLabel'], isEmpty);
    expect(tools()['arousalLevel'], 0, reason: 'chat tools');
    expect(tools()['refractoryLabel'], isEmpty);
    expect(chat.getArousalForGroupCharacter(card), 60, reason: 'kept');

    await tester.runAsync(() => chat.setMemberAfterglowEnabled(card, true));
    await cardShowsBars(tester);
    expect(find.text('Lust: Intense'), findsOneWidget);
    expect(find.text(chip), findsOneWidget);
    expect((block()['arousal'] as Map)['level'], 60);
    expect(block()['refractoryLabel'], chip);
    expect(tools()['arousalLevel'], 60);
    expect(tools()['refractoryLabel'], chip);
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
    final bare = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/tools/member-recovery'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'id': id}),
      ),
    );
    expect(bare.statusCode, 400, reason: 'no Recovery block, no reset');
    expect(card.frontPorchExtensions?.recovery.recoveryMinutes, 45);

    await chat.setMemberAfterglowEnabled(card, false);
    expect(row()['afterglowRuns'], isFalse);
  });

  // The member card shows what runs for THAT member, as 1:1's Character
  // State does for the host: their own recovery under their Lust bar,
  // Ambitions and Pockets whatever the Realism switch says, and a portrait
  // wearing their own mood rather than one mood for the whole chat.
  group('the member card shows what is running for that member', () {
    List<ChatParticipant> members() =>
        chat.cast.where((p) => !p.isHost).toList();

    Future<void> pumpCard(
      WidgetTester tester,
      CharacterCard card, {
      VoidCallback? onOpenObjectives,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: GroupMemberCard(
                  character: card,
                  chatService: chat,
                  avatarColor: AppColors.formMasterAccent,
                  isNextSpeaker: false,
                  isExpanded: true,
                  onTap: () {},
                  onOpenObjectives: onOpenObjectives,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets("a member's own recovery countdown, while Afterglow runs for "
        'them', (tester) async {
      await tester.runAsync(boot);
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.runAsync(() async {
        await storage.realismSettings.setAdultThemesEnabled(true);
        await storage.realismSettings.setNsfwCooldownDefault(true);
      });
      final [ana, bea] = members();
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(ana.card),
        refractory: Refractory.fromMinutes(30),
      );
      final facade = ChatToolsFacade(chat, storage, null);
      Map<dynamic, dynamic> phoneTools(ChatParticipant who) =>
          facade.state(participantId: who.id)['nsfw'] as Map;
      Object? phoneFeed(ChatParticipant who) =>
          ChatRealismRead(chat).participantRealism(who.id)!['refractoryLabel'];

      await pumpCard(tester, ana.card);
      expect(
        find.textContaining('Refractory: '),
        findsOneWidget,
        reason: "her own countdown on her card",
      );
      expect(phoneTools(ana)['refractoryMinutesRemaining'], 30);
      expect(phoneTools(ana)['refractoryLabel'], startsWith('Refractory: '));
      expect(phoneFeed(ana), startsWith('Refractory: '));

      await pumpCard(tester, bea.card);
      expect(
        find.textContaining('Refractory'),
        findsNothing,
        reason: 'the other member has none of her own',
      );
      expect(phoneTools(bea)['refractoryMinutesRemaining'], 0);
      expect(phoneTools(bea)['refractoryLabel'], isEmpty);
      expect(phoneFeed(bea), isEmpty);

      await tester.runAsync(
        () => storage.realismSettings.setNsfwCooldownDefault(false),
      );
      await pumpCard(tester, ana.card);
      expect(
        find.textContaining('Refractory'),
        findsNothing,
        reason: 'Porch Life Afterglow off',
      );
      expect(phoneFeed(ana), isEmpty);
      await tester.runAsync(
        () => storage.realismSettings.setNsfwCooldownDefault(true),
      );
      await pumpCard(tester, ana.card);
      expect(
        find.textContaining('Refractory: '),
        findsOneWidget,
        reason: 'hidden while off, never erased',
      );
    });

    testWidgets("a member's Ambitions and Pockets show with Realism off, as "
        'in 1:1', (tester) async {
      await tester.runAsync(boot);
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.runAsync(() async {
        await storage.realismSettings.setPocketsEnabled(true);
        await storage.realismSettings.setObjectivesEnabled(true);
        await chat.setRealismEnabled(false);
      });
      final ana = members().first;
      ana.card.frontPorchExtensions =
          (ana.card.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            ambitions: ['Open a bakery by the river'],
          );
      expect(chat.isGroupRealismActive, isFalse);
      expect(chat.objectivesActive, isTrue);

      await pumpCard(tester, ana.card);
      expect(find.byType(AmbitionsRow), findsOneWidget);
      expect(find.byType(PocketsRow), findsOneWidget);
      expect(
        find.byType(RealismProgressRow),
        findsNothing,
        reason: 'the Realism rows stay off',
      );

      await tester.runAsync(
        () => storage.realismSettings.setPocketsEnabled(false),
      );
      await pumpCard(tester, ana.card);
      expect(
        find.byType(PocketsRow),
        findsNothing,
        reason: "Pockets' own switch still decides",
      );
    });

    testWidgets("a member's Objectives row follows Objectives, not Realism", (
      tester,
    ) async {
      await tester.runAsync(boot);
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.runAsync(() async {
        await storage.realismSettings.setObjectivesEnabled(true);
        await chat.setRealismEnabled(false);
      });
      final ana = members().first;
      await pumpCard(tester, ana.card, onOpenObjectives: () {});
      expect(find.textContaining('active objectives'), findsOneWidget);

      await tester.runAsync(
        () => storage.realismSettings.setObjectivesEnabled(false),
      );
      expect(chat.objectivesActive, isFalse);
      await pumpCard(tester, ana.card, onOpenObjectives: () {});
      expect(
        find.textContaining('active objectives'),
        findsNothing,
        reason: 'Objectives off in Porch Life',
      );
    });

    test("the phone's unfocused group view shows the panel owner's own "
        "recovery, never the loaded speaker's", () async {
      await boot();
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      final owner = members().first;
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(owner.card),
        refractory: Refractory.fromMinutes(30),
      );
      chat.nsfwService.setRefractory(Refractory.fromMinutes(45));

      final nsfw = ChatToolsFacade(chat, storage, null).state()['nsfw'] as Map;
      expect(nsfw['refractoryMinutesRemaining'], 30);
      expect(nsfw['refractoryLabel'], startsWith('Refractory: '));
      expect(ChatRealismRead(chat).snapshot()['refractoryLabel'], isEmpty);
    });

    test("the phone's unfocused group view says whether Afterglow runs for "
        "the panel owner, not the loaded speaker", () async {
      await boot();
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      final owner = members().first;
      await chat.setMemberAfterglowEnabled(owner.card, false);
      expect(
        chat.nsfwService.nsfwCooldownEnabled,
        isTrue,
        reason: 'the live scalars still read on',
      );

      Object? runs() =>
          (ChatToolsFacade(chat, storage, null).state()['nsfw']
              as Map)['cooldownEnabled'];
      expect(runs(), isFalse, reason: "the owner's own switch is off");
      await chat.setMemberAfterglowEnabled(owner.card, true);
      expect(runs(), isTrue);
    });

    test("the phone's unfocused group view shows the panel owner's own "
        "Lust, not the loaded speaker's", () async {
      await boot();
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      final owner = members().first;
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(owner.card),
        arousal: 20,
      );
      chat.nsfwService.setArousalLevel(70);
      final ladder = chat.nsfwService.arousalTierNameForLevel;
      expect(ladder(20), isNot(ladder(70)), reason: 'two different tiers');

      final nsfw = ChatToolsFacade(chat, storage, null).state()['nsfw'] as Map;
      expect(nsfw['arousalLevel'], 20);
      expect(nsfw['arousalTier'], ladder(20));
      final focused =
          ChatToolsFacade(
                chat,
                storage,
                null,
              ).state(participantId: owner.id)['nsfw']
              as Map;
      expect(focused['arousalLevel'], 20, reason: 'the same, focused');
    });

    List<face.AvatarImage> faces(String who) => [
      for (final (i, label) in ['neutral', 'joy', 'sadness', 'fear'].indexed)
        face.AvatarImage(
          id: '$who-$label',
          characterId: who,
          filename: '$who-$label.png',
          label: label,
          displayOrder: i,
          createdAt: DateTime.utc(2026),
        ),
    ];

    test("each member's portrait wears that member's own mood, on the "
        'desktop and the phone', () async {
      await boot();
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      await storage.expressionSettings.setExpressionEnabled(true);
      final [ana, bea] = members();
      ana.card.avatarImages = faces('ana');
      bea.card.avatarImages = faces('bea');
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(ana.card),
        emotion: 'joy',
      );
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(bea.card),
        emotion: 'sad',
      );

      expect(chat.resolveExpressionAvatar(ana.card)?.label, 'joy');
      expect(chat.resolveExpressionAvatar(bea.card)?.label, 'sadness');

      final dir = Directory(
        p.join(storage.charactersDir.path, 'Bea', 'avatars'),
      )..createSync(recursive: true);
      File(p.join(dir.path, 'bea-sadness.png')).writeAsBytesSync([1, 2, 3]);
      final router = shelf_router.Router();
      WebCharacterRoutes(
        CharacterFacade(db, storage, null, chat, null),
        router,
        thumbnails: ThumbnailCache(Directory.systemTemp),
      );
      final res = await router.call(
        shelf.Request(
          'GET',
          Uri.parse(
            'http://localhost/api/chat/expression-avatar'
            '?participant=${Uri.encodeQueryComponent(bea.id)}',
          ),
        ),
      );
      expect(res.statusCode, 200, reason: "the phone asks for Bea's own face");
      expect(await res.read().expand((b) => b).toList(), [1, 2, 3]);
      expect(
        ChatRealismRead(chat).participantRealism(bea.id)!['expressionLabel'],
        'sadness',
      );
    });

    testWidgets("the sidebar portrait's mood badge is the focused member's "
        'own', (tester) async {
      await tester.runAsync(boot);
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.runAsync(
        () => storage.expressionSettings.setExpressionEnabled(true),
      );
      final repo = CharacterRepository(db, storage);
      final [ana, bea] = members();
      ana.card.avatarImages = faces('ana');
      bea.card.avatarImages = faces('bea');
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(ana.card),
        emotion: 'joy',
      );
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(bea.card),
        emotion: 'sad',
      );
      Future<void> pumpPortrait(CharacterCard card) async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<CharacterRepository>.value(value: repo),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ChatSidebarPortrait(
                  character: card,
                  isGroup: true,
                  sidebarWidth: 280,
                  resolveCharImage: File.new,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpPortrait(ana.card);
      expect(find.text(EmotionLabels.emoji['joy']!), findsOneWidget);
      await pumpPortrait(bea.card);
      expect(find.text(EmotionLabels.emoji['sadness']!), findsOneWidget);
      expect(find.text(EmotionLabels.emoji['joy']!), findsNothing);
    });

    // A label read can ask the LLM (the side lane), so the phone reads a
    // member's face label only while Expressions are on and they have a
    // face to wear it, as the desktop sidebar does.
    test('with Expressions off, a member read asks the LLM nothing and the '
        'phone gets no mood picture', () async {
      await boot();
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      final asks = <String>[];
      final saved = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null && m.contains('[Expression] reclassify')) asks.add(m);
      };
      addTearDown(() => debugPrint = saved);
      final [ana, bea] = members();
      bea.card.avatarImages = faces('bea');
      for (final who in [ana, bea]) {
        chat.debugSeedGroupSpeakerState(
          chat.characterIdFor(who.card),
          emotion: 'wibbly',
        );
      }
      final dir = Directory(
        p.join(storage.charactersDir.path, 'Bea', 'avatars'),
      )..createSync(recursive: true);
      File(p.join(dir.path, 'bea-neutral.png')).writeAsBytesSync([1, 2, 3]);
      final router = shelf_router.Router();
      WebCharacterRoutes(
        CharacterFacade(db, storage, null, chat, null),
        router,
        thumbnails: ThumbnailCache(Directory.systemTemp),
      );
      Future<int> face(ChatParticipant who) async => (await router.call(
        shelf.Request(
          'GET',
          Uri.parse(
            'http://localhost/api/chat/expression-avatar'
            '?participant=${Uri.encodeQueryComponent(who.id)}',
          ),
        ),
      )).statusCode;
      Object? label(ChatParticipant who) =>
          ChatRealismRead(chat).participantRealism(who.id)!['expressionLabel'];

      expect(label(ana), isEmpty, reason: 'no face to wear');
      expect(label(bea), isEmpty, reason: 'Expressions off');
      expect(await face(bea), 404);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asks, isEmpty);

      await storage.expressionSettings.setExpressionEnabled(true);
      expect(label(ana), isEmpty, reason: 'still no face to wear');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asks, isEmpty);
      expect(label(bea), isNotNull);
      expect(await face(bea), 200);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asks, isNotEmpty, reason: 'with a face, the read asks');
    });

    testWidgets('with ONNX on, only the member whose reply the classifier '
        'read wears its label', (tester) async {
      await tester.runAsync(boot);
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.runAsync(
        () =>
            storage.expressionSettings.setExpressionClassificationMode('onnx'),
      );
      final lastReply = chat.messages.lastWhere(
        (m) => !m.isUser && m.text.isNotEmpty,
      );
      final writer = resolveGroupSpeakerForMessage(
        chat.groupCharacters,
        lastReply,
      )!;
      final other = chat.groupCharacters.firstWhere(
        (c) => chat.characterIdFor(c) != chat.characterIdFor(writer),
      );
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(writer),
        emotion: 'fear',
      );
      chat.debugSeedGroupSpeakerState(
        chat.characterIdFor(other),
        emotion: 'sad',
      );

      expect(
        chat.expressionLabelFor(writer),
        'fear',
        reason: 'nothing classified yet: the live label is nobody reading',
      );
      expect(chat.expressionLabelFor(other), 'sadness');

      // The scripted classifier only feeds the attribution under test.
      chat.setExpressionClassifierService(_ScriptedClassifier(storage));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final live = chat.currentExpressionLabel;
      expect(live, isNot('fear'));
      expect(chat.expressionLabelFor(writer), live);
      expect(chat.expressionLabelFor(other), 'sadness');
      chat.expressionService.resetForFreshChat();
    });
  });
}

/// Stands in for the ONNX model (no download): always the same reading.
class _ScriptedClassifier extends ExpressionClassifierService {
  _ScriptedClassifier(super.storage);

  @override
  Future<void> ensureInitialized({
    required String Function() getCurrentEmotion,
    required Future<String> Function(String unknownEmotion) reclassify,
  }) async {}

  @override
  Future<EmotionResult?> classify(String text) async =>
      const EmotionResult(emotion: 'surprise', confidence: 1);
}
