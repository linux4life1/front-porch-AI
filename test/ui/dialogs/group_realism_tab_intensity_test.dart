// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings → Realism drew a red error box instead of the tab. Its
// mood-strength dropdown offered calm / moderate / intense while a group is
// created with the engine's mild / moderate / strong (default mild), and a
// dropdown handed a value that is not one of its items fails its assertion.
// So every group made with the default broke the tab. A real group, so the
// seed comes through the real ChatService door the tab reads.
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
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/member_realism_card.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings_dialog.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart'
    show RealismFormSection;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_mood_').path;
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

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
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
    repo = GroupChatRepository(storage, db);

    // Ada as a new group seeds her (mild); Bex as the old tab saved her.
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ada': defaultGroupMemberRealismSeed(),
        'mem-bex': {
          ...defaultGroupMemberRealismSeed(),
          'emotionIntensity': 'intense',
        },
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-mood',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ada', 'Ada'), ('mem-bex', 'Bex')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-mood',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-mood',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: repo,
    );
    await chat.setRealismEnabled(true);
  }

  testWidgets('the Realism tab draws with the strengths groups are made with', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupRealismNeedsTab(chatService: chat, groupRepo: repo),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(GroupMemberRealismCard), findsNWidgets(2));
    // The strength is edited in each member's editor now, which reads the
    // group's seed for them; the old tab's `intense` reads as `strong`.
    final group = chat.activeGroup!;
    expect(
      [
        for (final id in ['mem-ada', 'mem-bex'])
          groupMemberStartIn(
            group.defaultMemberRealismState,
            id,
          )!.emotionIntensity,
      ],
      ['mild', 'strong'],
      reason: 'Ada as made; Bex read from intense',
    );
  });

  // Each member was a cut-down copy of the member editor here (bonds, mood,
  // the verifier). Now it says where they start and Edit opens their editor;
  // the chat's own controls for them stay.
  testWidgets("each member's summary says where they start in new chats and "
      "Edit opens their editor, whose group lines link to Group Settings", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    final library = CharacterRepository(db, storage);
    final worlds = WorldRepository(storage, db);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<CharacterRepository>.value(value: library),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<GroupChatRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupRealismNeedsTab(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.pump();

    final ada = find.widgetWithText(GroupMemberRealismCard, 'Ada');
    expect(
      find.descendant(of: ada, matching: find.text(' · Close / Trusting')),
      findsOneWidget,
      reason: "the group's seed for her: 35 / 40",
    );
    expect(find.text('Short-Term Bond'), findsNothing);
    expect(find.text('Director/Verifier'), findsNothing);

    await tester.tap(find.descendant(of: ada, matching: find.text('Edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditCharacterPage), findsOneWidget);
    expect(
      find.text("Where Ada starts in this group's new chats."),
      findsOneWidget,
    );

    final link = find.text('Group Settings ›').first;
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(
        of: find.byType(GroupSettingsDialog),
        matching: find.text('Realism — The Porch'),
      ),
      findsOneWidget,
      reason: "the group's Realism lines open Group Settings on Realism",
    );
    Navigator.of(tester.element(find.byType(GroupSettingsDialog))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    Navigator.of(tester.element(find.byType(EditCharacterPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  // Opened from inside Group Settings, the editor's group lines opened a
  // second Group Settings over the first. They close the editor back to the
  // dialog it came from, on the tab the line names.
  testWidgets("a member's editor opened from Group Settings links back to "
      'its tab, not to a second Group Settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    final library = CharacterRepository(db, storage);
    final worlds = WorldRepository(storage, db);
    final shown = <int>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<CharacterRepository>.value(value: library),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<GroupChatRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupRealismNeedsTab(
              chatService: chat,
              groupRepo: repo,
              onShowTab: shown.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final ada = find.widgetWithText(GroupMemberRealismCard, 'Ada');
    await tester.tap(find.descendant(of: ada, matching: find.text('Edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final link = find.text('Group Settings ›').first;
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Read, then close whatever is still open before checking: a check
    // failing over open dialogs would leave the chat unable to close.
    final stacked = find.byType(GroupSettingsDialog).evaluate().length;
    final editorOpen = find.byType(EditCharacterPage).evaluate().isNotEmpty;
    Navigator.of(
      tester.element(find.byType(GroupRealismNeedsTab).first),
    ).popUntil((r) => r.isFirst);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // What the closed dialogs started on the real database settles here.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(
      stacked,
      0,
      reason: 'THE BUG: a second Group Settings opened over the first',
    );
    expect(editorOpen, isFalse);
    expect(shown, [2], reason: 'back on Group Settings → Realism');
  });

  group("the group chat's own Afterglow switch", () {
    Future<void> pumpTab(WidgetTester tester, {required bool allowed}) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await boot();
        await storage.realismSettings.setAdultThemesEnabled(allowed);
        await storage.realismSettings.setNsfwCooldownDefault(allowed);
      });
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(chat, db)),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: GroupRealismNeedsTab(chatService: chat, groupRepo: repo),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Finder afterglowSwitch() => find.descendant(
      of: find
          .ancestor(of: find.text('Afterglow'), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );

    testWidgets('Porch Life allows it: the tab shows it, and it switches '
        'this chat', (tester) async {
      await pumpTab(tester, allowed: true);
      expect(tester.widget<Switch>(afterglowSwitch()).value, isTrue);

      await tester.ensureVisible(afterglowSwitch());
      await tester.tap(afterglowSwitch());
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(chat.afterglowChatSwitch, isFalse);
      expect(
        chat.nsfwService.nsfwCooldownEnabled,
        isFalse,
        reason: "the gate reads this chat's switch",
      );
      expect(tester.widget<Switch>(afterglowSwitch()).value, isFalse);
    });

    testWidgets('Porch Life Afterglow off: no switch', (tester) async {
      await pumpTab(tester, allowed: false);
      expect(find.text('Afterglow'), findsNothing);
    });

    testWidgets("each member's own switch sits on their card, and switches "
        'that member alone', (tester) async {
      await pumpTab(tester, allowed: true);
      final ada = chat.groupCharacters.firstWhere((c) => c.name == 'Ada');
      final bex = chat.groupCharacters.firstWhere((c) => c.name == 'Bex');
      final adaSwitch = find.descendant(
        of: find.widgetWithText(GroupMemberRealismCard, 'Ada'),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(adaSwitch).value, isTrue);

      await tester.ensureVisible(adaSwitch);
      var saved = false;
      void done() => saved = true;
      chat.addListener(done);
      await tester.tap(adaSwitch);
      // The switch saves Ada's card through the chat's database, real I/O the
      // test clock does not drive; the chat tells its listeners once it is
      // done.
      for (var i = 0; i < 500 && !saved; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      chat.removeListener(done);
      expect(saved, isTrue, reason: 'the switch saved');
      final rows = await tester.runAsync(
        () => repo.getMembersForGroup('grp-mood'),
      );
      final adaRow = rows!.firstWhere((m) => m.id == 'mem-ada');
      expect(
        FrontPorchExtensions.fromJson(
          adaRow.frontPorchExtensions!,
        ).afterglowEnabled,
        isFalse,
        reason: "kept on Ada's own row in this group",
      );
      expect(chat.afterglowRunsFor(ada), isFalse);
      expect(chat.afterglowRunsFor(bex), isTrue);
    });

    testWidgets("each member's Recovery block sits under their own switch, "
        'saves to that member, and hides while their switch is off', (
      tester,
    ) async {
      await pumpTab(tester, allowed: true);
      final adaCard = find.widgetWithText(GroupMemberRealismCard, 'Ada');
      final adaBlock = find.descendant(
        of: adaCard,
        matching: find.byType(RecoveryBlock),
      );
      expect(adaBlock, findsOneWidget);

      // Both edits save through the chat's database, real I/O the test clock
      // does not drive; the chat tells its listeners once a save is done.
      Future<void> untilSaved(Future<void> Function() edit) async {
        var saved = false;
        void done() => saved = true;
        chat.addListener(done);
        await edit();
        for (var i = 0; i < 500 && !saved; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
        }
        chat.removeListener(done);
        expect(saved, isTrue, reason: 'the edit saved');
      }

      await untilSaved(
        () async => tester
            .widget<RecoveryBlock>(adaBlock)
            .onChanged(RecoveryProfile.auto.withMinutes(60)),
      );
      final rows = await tester.runAsync(
        () => repo.getMembersForGroup('grp-mood'),
      );
      expect(
        FrontPorchExtensions.fromJson(
          rows!.firstWhere((m) => m.id == 'mem-ada').frontPorchExtensions!,
        ).recovery.recoveryMinutes,
        60,
        reason: "kept on Ada's own row in this group",
      );

      final adaSwitch = find.descendant(
        of: adaCard,
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(adaSwitch);
      await untilSaved(() => tester.tap(adaSwitch));
      await tester.pump();
      expect(adaBlock, findsNothing, reason: 'her own switch is off');
    });
  });

  /// The group's blobs with Ada starting at [affection] / [trust].
  String adaAt(int affection, int trust) => buildGroupRealismBlobs(
    seeds: {
      'mem-ada': {
        ...defaultGroupMemberRealismSeed(),
        'affection': affection,
        'longTermScore': affection,
        'trust': trust,
      },
      'mem-bex': defaultGroupMemberRealismSeed(),
    },
    needsEnabled: true,
    timeOfDay: 'morning',
    dayCount: 1,
  ).defaultMemberJson;

  // The summary read this chat's copy of the group, which holds Group
  // Settings edits Done has not saved; the group's next New Chat starts
  // from its saved row, as the phone's summary says.
  testWidgets("each member's summary reads the group's saved row, not this "
      "chat's unsaved copy", (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    chat.activeGroup!.defaultMemberRealismState = adaAt(300, 100);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupRealismNeedsTab(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.widgetWithText(GroupMemberRealismCard, 'Ada'),
        matching: find.text(' · Close / Trusting'),
      ),
      findsOneWidget,
      reason: "the saved row: 35 / 40, not the copy's 300 / 100",
    );
  });

  // Group Settings opened from a member's editor can save the group (Done).
  // The editor kept the start it read as it opened, so its Save wrote that
  // back over the one just saved.
  testWidgets("a member's editor reads her start again when its Group "
      'Settings link closes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    final library = CharacterRepository(db, storage);
    final worlds = WorldRepository(storage, db);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<CharacterRepository>.value(value: library),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<GroupChatRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupRealismNeedsTab(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    final ada = find.widgetWithText(GroupMemberRealismCard, 'Ada');
    await tester.tap(find.descendant(of: ada, matching: find.text('Edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    RealismFormSection form() =>
        tester.widget<RealismFormSection>(find.byType(RealismFormSection));
    expect(form().shortTermBond, 35);

    // The group's row moves after the editor read it, as Group Settings'
    // Done writes it. One plain statement: a write that wakes the table's
    // watchers waits on their reads, which only a frame moves on.
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE groups SET default_member_realism_state = ? WHERE id = ?',
        [adaAt(90, 10), 'grp-mood'],
      ),
    );
    await tester.pump();
    expect(form().shortTermBond, 35, reason: 'nothing read it yet');

    final link = find.text('Group Settings ›').first;
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    Navigator.of(tester.element(find.byType(GroupSettingsDialog))).pop();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      (form().shortTermBond, form().trustLevel),
      (90, 10),
      reason: 'the start the group saved',
    );
    Navigator.of(tester.element(find.byType(EditCharacterPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  // Save writes the group's row and keeps Group Settings open. The members'
  // summaries kept the row they read as the dialog opened.
  testWidgets("Group Settings' Save brings the members' summaries up to the "
      'row it wrote', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<GroupChatRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GroupSettingsDialog(
              chatService: chat,
              groupRepo: repo,
              initialTab: 2,
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    await settle();
    final ada = find.widgetWithText(GroupMemberRealismCard, 'Ada');
    final asOpened = find.descendant(
      of: ada,
      matching: find.text(' · Close / Trusting'),
    );
    expect(asOpened, findsOneWidget);

    // An edit in this chat's copy, as the dialog's own controls make one.
    chat.activeGroup!.defaultMemberRealismState = adaAt(300, 100);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await settle();

    final row = await tester.runAsync(() => db.getGroupById('grp-mood'));
    expect(
      parseGroupRealismSeeds(
        row!.defaultMemberRealismState,
      )['mem-ada']!['trust'],
      100,
      reason: 'Save wrote the row',
    );
    expect(ada, findsOneWidget, reason: 'the dialog stays open');
    expect(asOpened, findsNothing, reason: 'the summary reads the saved row');
  });
}
