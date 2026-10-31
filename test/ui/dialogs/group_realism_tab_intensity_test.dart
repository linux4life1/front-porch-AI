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
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/member_realism_card.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/recovery_block.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
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
    final shown = tester
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .map((d) => d.initialValue)
        .where(emotionIntensities.contains)
        .toList();
    expect(shown, [
      'mild',
      'strong',
    ], reason: 'Ada as made; Bex read from intense');
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
      Future<void> untilSaved(void Function() edit) async {
        var saved = false;
        void done() => saved = true;
        chat.addListener(done);
        edit();
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
        () => tester
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
}
