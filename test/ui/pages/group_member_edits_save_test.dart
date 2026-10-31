// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Edits to a group member save to the member's own row. A member is the
// group's private copy of a character (group_members), and the group loads
// its members from those rows, so an edit that never reached the row was
// gone the next time the group opened. Three ways in lost edits:
//
// - Edit Character from a group's sidebar ran the library writer: it rewrote
//   the member's PNG, updated a `characters` row that does not exist, and
//   re-keyed memories filed under the character's bare name (that guard is
//   pinned in test/services/character_repository_test.dart).
// - UI Settings from a group's sidebar (chat colours, avatar lock) did the
//   same through the library repository.
// - Edit group's per-member Edit showed Voice and the greeting seeds and
//   saved neither.
//
// The chat keeps its own copy of each member, so a save from the chat must
// not put back values Edit group saved since: UI Settings writes only the
// extensions, and Edit group replaces the chat's copy when the group is open.
//
// Red proofs: drop the member branch in showEditCharacterDialog (test 1) or
// in UiSettingsDialog._updateCharacterExtension (test 2); have UI Settings
// write the whole card (test 2); put back Edit group's content-only write
// (test 3, voice); drop the extensions write in
// EditCharacterCardWriter.writeFields (test 3, seed); drop Edit group's
// refresh of the chat's copy (test 4); write a null extensions column when
// the card holds none (test 5).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/drift.dart' show TableInfo, TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings/ui_settings_controls.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings_dialog.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar_widgets.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show MemberGroupView, memberGroupViewOfTemplate;
import 'package:front_porch_ai/ui/pages/edit_group/edit_group.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart'
    show legacyCardExtSeedKeys;
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart'
    show GroupWideLine;
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/double_tap.dart';

const _groupId = 'grp-edits';
const _memberId = 'mem-mara';

/// A group chat open on [members]. Its roster refresh replaces the member by
/// row id, as ChatService's does, and records what it was handed.
class _OpenGroup extends FakeChatService {
  _OpenGroup(List<CharacterCard> members) : members = List.of(members);

  final List<CharacterCard> members;
  final refreshed = <CharacterCard>[];

  @override
  bool get isGroupMode => members.isNotEmpty;

  @override
  List<CharacterCard> get groupCharacters => members;

  @override
  void refreshActiveCharacterCard(CharacterCard card) {
    refreshed.add(card);
    final i = members.indexWhere((c) => c.dbId == card.dbId);
    if (i != -1) members[i] = card;
  }
}

/// The library. The Details tab asks it for a cover; the shared fake throws
/// for cards it does not hold. (`updateCharacter` is an extension, so a test
/// double cannot record it: the member's row is the evidence.)
class _Library extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    // Same isolate: drift's futures must complete inside runAsync.
    db = AppDatabase.forTesting(sameIsolate: true);
    await db.insertGroup(GroupsCompanion.insert(id: _groupId, name: 'Pair'));
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: _memberId,
        groupId: _groupId,
        name: 'Mara',
        description: const Value('Keeps the lighthouse.'),
        alternateGreetings: Value(jsonEncode(['You came back.'])),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<GroupMemberRow> memberRow() async =>
      (await db.getGroupMembers(_groupId)).single;

  CharacterCard member({String description = 'Keeps the lighthouse.'}) =>
      CharacterCard(
        name: 'Mara',
        description: description,
        alternateGreetings: ['You came back.'],
      )..dbId = _memberId;

  /// Pumps frames until [done] holds. Under runAsync, pumpAndSettle returns
  /// as soon as no frame is scheduled, before the awaited writes behind a
  /// save have run; each step waits real time for those writes and advances
  /// the frame clock so route animations finish.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    required String why,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out: $why');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required ChatService chat,
    required void Function(BuildContext) onOpen,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = _Library();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    addTearDown(library.dispose);
    addTearDown(storage.dispose);
    addTearDown(worlds.dispose);
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<CharacterRepository>.value(value: library),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onOpen(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  void pickVoice(WidgetTester tester, String voice) => tester
      .widget<CharacterVoicePicker>(find.byType(CharacterVoicePicker))
      .onChanged(voice);

  /// Save closes the editor only when the save went through; an error keeps
  /// it open behind a snackbar.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      () => find.byType(EditCharacterPage).evaluate().isEmpty,
      why: 'Save never closed the editor (it failed)',
    );
  }

  testWidgets('Edit Character on a group member saves to the member\'s '
      'row', (tester) async {
    await tester.runAsync(() async {
      final mara = member();
      final chat = _OpenGroup([mara]);
      await pumpHost(
        tester,
        chat: chat,
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      pickVoice(tester, 'af_heart');
      await tester.pump();
      await save(tester);

      expect(
        (await memberRow()).ttsVoice,
        'af_heart',
        reason:
            'THE BUG: the edit went to the library writer and the row '
            'never changed, so it was gone the next time the group opened',
      );
      expect(chat.refreshed, [same(mara)], reason: 'the roster shows the edit');
    });
  });

  testWidgets('UI Settings on a group member saves its extensions and puts '
      'nothing else back', (tester) async {
    await tester.runAsync(() async {
      // Edit group saved a new description and a voice since the chat
      // loaded its copy of Mara.
      await db.updateGroupMember(
        const GroupMembersCompanion(
          id: Value(_memberId),
          description: Value('Keeps the lamp and logs the ships.'),
          ttsVoice: Value('af_heart'),
        ),
      );
      final stale = member();
      final chat = _OpenGroup([stale]);
      await pumpHost(
        tester,
        chat: chat,
        onOpen: (context) => showDialog<void>(
          context: context,
          builder: (_) => UiSettingsDialog(character: stale),
        ),
      );

      tester
          .widget<AvatarLockToggle>(find.byType(AvatarLockToggle))
          .onChanged(true);
      await pumpUntil(
        tester,
        () => chat.refreshed.isNotEmpty,
        why: 'the lock never saved',
      );

      final row = await memberRow();
      expect(
        row.frontPorchExtensions,
        isNotNull,
        reason: 'the lock never reached the row',
      );
      final ext = FrontPorchExtensions.fromJson(
        jsonDecode(row.frontPorchExtensions!) as Map<String, dynamic>,
      );
      expect(ext.avatarLocked, isTrue);
      expect(
        (row.description, row.ttsVoice),
        ('Keeps the lamp and logs the ships.', 'af_heart'),
        reason:
            'a whole-row write from the chat\'s older copy undid the '
            'Edit group save',
      );
    });
  });

  testWidgets('Edit group\'s member Edit saves the voice and the greeting '
      'seeds it shows', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      pickVoice(tester, 'af_heart');
      await tester.pump();
      await tester.tap(find.text('Dialogue'));
      await tester.pumpAndSettle();
      tester
          .widget<GreetingSeedForm>(find.byType(GreetingSeedForm).first)
          .onChanged(const GreetingRealismSeed(characterEmotion: 'wary'));
      await tester.pump();
      await save(tester);

      final row = await memberRow();
      expect(row.ttsVoice, 'af_heart', reason: 'Voice was shown, not saved');
      expect(
        row.frontPorchExtensions,
        isNotNull,
        reason: 'the greeting\'s seed was shown on Dialogue, not saved',
      );
      final ext = FrontPorchExtensions.fromJson(
        jsonDecode(row.frontPorchExtensions!) as Map<String, dynamic>,
        alternateGreetings: const ['You came back.'],
      );
      expect(
        ext.greetingSeeds.first?.characterEmotion,
        'wary',
        reason: 'the greeting\'s seed was shown on Dialogue, not saved',
      );
    });
  });

  testWidgets('Edit group\'s member Edit replaces the open chat\'s copy of '
      'the member', (tester) async {
    await tester.runAsync(() async {
      final chat = _OpenGroup([member()]);
      await pumpHost(
        tester,
        chat: chat,
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      pickVoice(tester, 'af_heart');
      await tester.pump();
      await save(tester);

      expect(
        chat.members.single.ttsVoice,
        'af_heart',
        reason:
            'the chat kept its older copy, so its next save would put '
            'the old voice back',
      );
    });
  });

  testWidgets('Edit group\'s member Edit keeps extensions it could not '
      'read', (tester) async {
    await tester.runAsync(() async {
      // Imported from a foreign group card: a whole-number field stored as
      // a decimal. The member loads with no extensions at all.
      const foreign = '{"realism_engine":{"day_count":2.0}}';
      await db.updateGroupMember(
        const GroupMembersCompanion(
          id: Value(_memberId),
          frontPorchExtensions: Value(foreign),
        ),
      );
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      pickVoice(tester, 'af_heart');
      await tester.pump();
      await save(tester);

      final row = await memberRow();
      expect(row.ttsVoice, 'af_heart');
      expect(
        row.frontPorchExtensions,
        foreign,
        reason: 'a card that loaded without extensions wrote NULL over them',
      );
    });
  });

  /// The editor host with Porch Life allowing Afterglow, so the member's own
  /// switch shows.
  Future<void> pumpAfterglowHost(
    WidgetTester tester, {
    required ChatService chat,
    required void Function(BuildContext) onOpen,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = _Library();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    addTearDown(library.dispose);
    addTearDown(storage.dispose);
    addTearDown(worlds.dispose);
    addTearDown(chat.dispose);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<CharacterRepository>.value(value: library),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onOpen(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder afterglowSwitch(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(Switch),
  );

  FrontPorchExtensions? rowExtensions(GroupMemberRow row) =>
      row.frontPorchExtensions == null
      ? null
      : FrontPorchExtensions.fromJson(
          jsonDecode(row.frontPorchExtensions!) as Map<String, dynamic>,
        );

  testWidgets("Edit group's member Edit is Edit Character for the member: "
      'it says whose copy it is and saves their own Afterglow', (tester) async {
    await tester.runAsync(() async {
      await pumpAfterglowHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member()..frontPorchExtensions = FrontPorchExtensions(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      final banner = find.byKey(const Key('group-member-editor-banner'));
      expect(banner, findsOneWidget, reason: 'the editor says whose copy');
      expect(tester.widget<Text>(banner).data, startsWith('Mara in Pair.'));
      expect(
        find.text('Enable Realism Engine'),
        findsNothing,
        reason: "Realism on or off is the group's, in Group Settings",
      );
      tester.widget<Switch>(afterglowSwitch('Afterglow for Mara')).onChanged!(
        false,
      );
      await tester.pump();
      await save(tester);

      expect(
        rowExtensions(await memberRow())?.afterglowEnabled,
        isFalse,
        reason: "Mara's own Afterglow reached her row in this group",
      );
    });
  });

  testWidgets("the chat sidebar's member Edit sets a changed Afterglow "
      'through the chat, which clears her Lust', (tester) async {
    await tester.runAsync(() async {
      final mara = member()..frontPorchExtensions = FrontPorchExtensions();
      final chat = _AfterglowGroup([mara]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('group-member-editor-banner')))
            .data,
        startsWith('Mara in Pair.'),
      );
      tester.widget<Switch>(afterglowSwitch('Afterglow for Mara')).onChanged!(
        false,
      );
      await tester.pump();
      await save(tester);

      expect(
        chat.afterglowSets,
        hasLength(1),
        reason:
            'the editor set the switch on the card itself, so the chat '
            'never cleared her Lust and cooldown',
      );
      expect(chat.afterglowSets.single.$1, same(mara));
      expect(chat.afterglowSets.single.$2, isFalse);
      expect(mara.frontPorchExtensions?.afterglowEnabled, isFalse);
      expect(rowExtensions(await memberRow())?.afterglowEnabled, isFalse);
    });
  });

  testWidgets("Edit group's member Edit sets a changed Afterglow through the "
      'open chat', (tester) async {
    await tester.runAsync(() async {
      final live = member()..frontPorchExtensions = FrontPorchExtensions();
      final chat = _AfterglowGroup([live]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        // Edit group's own copy, loaded from the row, not the chat's.
        onOpen: (context) => editGroupMemberCard(
          context,
          member()..frontPorchExtensions = FrontPorchExtensions(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      tester.widget<Switch>(afterglowSwitch('Afterglow for Mara')).onChanged!(
        false,
      );
      await tester.pump();
      await save(tester);

      expect(
        chat.afterglowSets,
        hasLength(1),
        reason: 'the chat never cleared her Lust and cooldown',
      );
      expect(chat.afterglowSets.single.$1, same(chat.members.single));
      expect(chat.afterglowSets.single.$2, isFalse);
      expect(rowExtensions(await memberRow())?.afterglowEnabled, isFalse);
    });
  });

  testWidgets("Edit group's member Edit keeps an Afterglow switched off in "
      'the chat since Edit group loaded the member', (tester) async {
    await tester.runAsync(() async {
      // Group Settings switched Mara's own Afterglow off after Edit group
      // loaded her with it on.
      final off = FrontPorchExtensions(afterglowEnabled: false);
      await db.updateGroupMember(
        GroupMembersCompanion(
          id: const Value(_memberId),
          frontPorchExtensions: Value(jsonEncode(off.toJson())),
        ),
      );
      final chat = _AfterglowGroup([member()..frontPorchExtensions = off]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        onOpen: (context) => editGroupMemberCard(
          context,
          member()..frontPorchExtensions = FrontPorchExtensions(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      pickVoice(tester, 'af_heart');
      await tester.pump();
      await save(tester);

      final row = await memberRow();
      expect(row.ttsVoice, 'af_heart');
      expect(
        rowExtensions(row)?.afterglowEnabled,
        isFalse,
        reason: "Edit group's older copy put her switch back on",
      );
      expect(
        chat.members.single.frontPorchExtensions?.afterglowEnabled,
        isFalse,
      );
      expect(chat.afterglowSets, isEmpty);
    });
  });

  testWidgets("a member editor keeps extensions it could not read when its "
      'Realism settings are changed', (tester) async {
    await tester.runAsync(() async {
      const foreign = '{"realism_engine":{"day_count":2.0}}';
      await db.updateGroupMember(
        const GroupMembersCompanion(
          id: Value(_memberId),
          frontPorchExtensions: Value(foreign),
        ),
      );
      await pumpAfterglowHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      tester.widget<Switch>(afterglowSwitch('Afterglow for Mara')).onChanged!(
        false,
      );
      pickVoice(tester, 'af_heart');
      await tester.pump();
      await save(tester);

      final row = await memberRow();
      expect(row.ttsVoice, 'af_heart', reason: 'the rest of the edit saves');
      expect(
        row.frontPorchExtensions,
        foreign,
        reason: 'defaults built over unreadable extensions replaced them',
      );
    });
  });

  testWidgets("the chat sidebar's member Edit leaves extensions it could not "
      "read to the open chat, setting no Afterglow", (tester) async {
    await tester.runAsync(() async {
      const foreign = '{"realism_engine":{"day_count":2.0}}';
      await db.updateGroupMember(
        const GroupMembersCompanion(
          id: Value(_memberId),
          frontPorchExtensions: Value(foreign),
        ),
      );
      final mara = member();
      final chat = _AfterglowGroup([mara]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      tester.widget<Switch>(afterglowSwitch('Afterglow for Mara')).onChanged!(
        false,
      );
      await tester.pump();
      await save(tester);

      expect((await memberRow()).frontPorchExtensions, foreign);
      expect(
        mara.frontPorchExtensions,
        isNull,
        reason: "the chat's copy kept the editor's defaults to write later",
      );
      expect(
        chat.afterglowSets,
        isEmpty,
        reason: 'the settle would persist the defaults over the row',
      );
    });
  });

  testWidgets("Edit group's member Edit on a copy with no extensions keeps "
      "the open chat's Afterglow", (tester) async {
    await tester.runAsync(() async {
      // Edit group loaded Mara before she had extensions; since then the
      // phone switched her Afterglow off.
      final off = FrontPorchExtensions(afterglowEnabled: false);
      await db.updateGroupMember(
        GroupMembersCompanion(
          id: const Value(_memberId),
          frontPorchExtensions: Value(jsonEncode(off.toJson())),
        ),
      );
      final chat = _AfterglowGroup([member()..frontPorchExtensions = off]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
        ),
      );

      pickVoice(tester, 'af_heart');
      await tester.pump();
      await save(tester);

      expect((await memberRow()).ttsVoice, 'af_heart');
      expect(rowExtensions(await memberRow())?.afterglowEnabled, isFalse);
      expect(
        chat.members.single.frontPorchExtensions?.afterglowEnabled,
        isFalse,
      );
      expect(
        chat.afterglowSets,
        isEmpty,
        reason: 'the settle switched her Afterglow back on',
      );
    });
  });

  // ── The member editor, finished to the mock ──
  //
  // The group's own switches show as read-only lines (a group never has two
  // switches for one thing), and where the member starts in the group's new
  // chats is the group's seed for her, never her card's own bonds.

  /// The group's row with Realism on for new chats, as the wizard saves it.
  Future<void> seedGroupRow() => db.updateGroup(
    GroupsCompanion(
      id: const Value(_groupId),
      defaultMemberRealismState: Value(_realismOn.defaultMemberJson),
      baselineRealismState: Value(_realismOn.baselineJson),
    ),
  );

  RealismFormSection form(WidgetTester tester) =>
      tester.widget<RealismFormSection>(find.byType(RealismFormSection));

  /// Counts writes to [table] from here on.
  int Function() countWrites(TableInfo<dynamic, dynamic> table) {
    var n = 0;
    final sub = db
        .tableUpdates(TableUpdateQuery.onTable(table))
        .listen((_) => n++);
    addTearDown(sub.cancel);
    return () => n;
  }

  Future<void> saveTwiceFast(WidgetTester tester) async {
    await doubleTapNoFrame(tester, find.text('Save'));
    await pumpUntil(
      tester,
      () => find.byType(EditCharacterPage).evaluate().isEmpty,
      why: 'Save never closed the editor (it failed)',
    );
    // Let the change notifications of the last write arrive.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  testWidgets("the chat sidebar's member editor shows the group's switches "
      "as lines and saves her start to the group's seed, once", (tester) async {
    await tester.runAsync(() async {
      await seedGroupRow();
      final mara = member();
      final open = GroupChat(
        id: _groupId,
        name: 'Pair',
        defaultMemberRealismState: _realismOn.defaultMemberJson,
        baselineRealismState: _realismOn.baselineJson,
      );
      final chat = _SeededGroup([mara], open);
      await pumpHost(
        tester,
        chat: chat,
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(find.text('Realism Engine · On in this chat'), findsOneWidget);
      expect(find.text('Chaos Mode · Off in this chat'), findsOneWidget);
      expect(find.text('Needs · On in this chat'), findsOneWidget);
      expect(
        find.textContaining('Time & Day · in this chat: '),
        findsOneWidget,
      );
      expect(
        find.text('Enable Realism Engine'),
        findsNothing,
        reason: 'the group never gets a second Realism switch',
      );
      expect(
        find.text("Where Mara starts in this group's new chats."),
        findsOneWidget,
      );
      expect(
        (form(tester).shortTermBond, form(tester).trustLevel),
        (35, 40),
        reason: "the group's seed for her, as the wizard saved it",
      );

      form(tester).onShortTermBondChanged(90);
      await tester.pump();
      form(tester).onLongTermBondChanged(150);
      await tester.pump();
      form(tester).onTrustLevelChanged(-30);
      await tester.pump();
      form(tester).onEmotionChanged('wary');
      await tester.pump();
      final groupWrites = countWrites(db.groups);
      final memberWrites = countWrites(db.groupMembers);
      await saveTwiceFast(tester);

      final row = (await db.getGroupById(_groupId))!;
      final seed = parseGroupRealismSeeds(
        row.defaultMemberRealismState,
      )[_memberId]!;
      expect(
        [
          seed['affection'],
          seed['longTermScore'],
          seed['trust'],
          seed['emotion'],
        ],
        [90, 150, -30, 'wary'],
        reason: "her start is the group's seed for her",
      );
      final baseline =
          (jsonDecode(row.baselineRealismState) as Map)[_memberId] as Map;
      expect(
        [baseline['affection'], baseline['longTermScore'], baseline['trust']],
        [90, 150, -30],
      );
      expect(
        parseGroupRealismSeeds(
          open.defaultMemberRealismState,
        )[_memberId]!['affection'],
        90,
        reason: "the open chat's next New Chat starts there",
      );
      expect(
        rowExtensions(await memberRow())?.shortTermBond,
        isNot(90),
        reason: "never her card's own bonds",
      );
      expect(groupWrites(), 1, reason: 'one Save, one start write');
      expect(memberWrites(), 1, reason: 'one Save, one row write');
    });
  });

  testWidgets("Edit group's member editor saves her start to the group's row "
      "and hands it to the page; Long-Term Bond keeps its own key", (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedGroupRow();
      String? handed;
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
          memberGroup: memberGroupViewOfTemplate(
            context,
            group: GroupChat(id: _groupId, name: 'Pair'),
            memberId: _memberId,
            memberExtensions: null,
            defaultMemberJson: _realismOn.defaultMemberJson,
            baselineJson: _realismOn.baselineJson,
            onStartSaved: (d, _) => handed = d,
          ),
        ),
      );

      expect(
        find.text("Realism Engine · On for this group's new chats"),
        findsOneWidget,
      );
      form(tester).onLongTermBondChanged(120);
      await tester.pump();
      final groupWrites = countWrites(db.groups);
      await saveTwiceFast(tester);

      final seed = parseGroupRealismSeeds(
        (await db.getGroupById(_groupId))!.defaultMemberRealismState,
      )[_memberId]!;
      expect(
        (seed['longTermScore'], seed['trust']),
        (120, 40),
        reason: 'Long-Term Bond went into trust',
      );
      expect(
        parseGroupRealismSeeds(handed!)[_memberId]!['longTermScore'],
        120,
        reason: "Edit group's own Save keeps the start it shows",
      );
      expect(groupWrites(), 1);
    });
  });

  testWidgets("a group whose new chats start without Realism shows it off "
      'and has no start to set', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          groupName: 'Pair',
          memberGroup: memberGroupViewOfTemplate(
            context,
            group: GroupChat(id: _groupId, name: 'Pair'),
            memberId: _memberId,
            memberExtensions: null,
            defaultMemberJson: '{}',
            baselineJson: '{}',
          ),
        ),
      );

      expect(
        find.text("Realism Engine · Off for this group's new chats"),
        findsOneWidget,
      );
      expect(
        find.text('Short-Term Bond'),
        findsNothing,
        reason: 'a seed written here would switch Realism on for the group',
      );
      expect(
        find.text(
          "This group's new chats start without Realism, so there's no start "
          'to set. Set in the Realism & Dynamics tab.',
        ),
        findsOneWidget,
      );
      final groupWrites = countWrites(db.groups);
      pickVoice(tester, 'af_heart');
      await tester.pump();
      await saveTwiceFast(tester);
      expect(groupWrites(), 0);
      expect(
        (await db.getGroupById(_groupId))!.defaultMemberRealismState,
        '{}',
      );
    });
  });

  testWidgets("Edit group's member editor links the group's lines back to "
      'its Realism & Dynamics tab', (tester) async {
    await tester.runAsync(() async {
      bool? toRealism;
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) async {
          toRealism = await editGroupMemberFromEditGroup(
            context,
            group: GroupChat(id: _groupId, name: 'Pair'),
            member: member(),
            memberId: _memberId,
            defaultMemberJson: _realismOn.defaultMemberJson,
            baselineJson: _realismOn.baselineJson,
            settingId: null,
            inheritCharacterLorebooks: true,
            onStartSaved: (_, _) {},
          );
        },
      );

      final link = find.text('Realism & Dynamics ›').first;
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await pumpUntil(
        tester,
        () => toRealism != null,
        why: 'the link never closed the editor',
      );
      expect(toRealism, isTrue, reason: 'the page shows its Realism tab');
    });
  });

  testWidgets("a member editor says what the group does with her greetings, "
      'lorebook and worlds', (tester) async {
    await tester.runAsync(() async {
      final mara = member();
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], GroupChat(id: _groupId, name: 'Pair')),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      await tester.tap(find.text('Dialogue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Used when this greeting opens a chat of this group.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Lorebook'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          "Mara's lorebook. The group reads it when Group Settings → "
          'Lorebook & Worlds has "Inherit character lorebooks" on; it is off',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Worlds'));
      await tester.pumpAndSettle();
      // A group turn reads the speaker's own worlds' lore while the group
      // inherits lorebooks; only the place and weather are the group's alone.
      expect(
        find.text(
          "This group has no Setting world yet: the group's world sets the "
          'place and weather, and is set in Group Settings. While Group '
          'Settings → Lorebook & Worlds has "Inherit character lorebooks" on, '
          "Mara's own worlds add their lore when Mara speaks; it is off for "
          'this group.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining("aren't used in a group"), findsNothing);
    });
  });

  testWidgets("a member editor says the group shares one scenario", (
    tester,
  ) async {
    await tester.runAsync(() async {
      final mara = member();
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], GroupChat(id: _groupId, name: 'Pair')),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );
      expect(
        find.text(
          'The group shares one scene: it uses its own Scenario, or, while '
          "it has none, its first member's.",
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a lite member keeps Realism, Needs and Afterglow for when '
      'she is promoted', (tester) async {
    await tester.runAsync(() async {
      await seedGroupRow();
      final mara = member()
        ..frontPorchExtensions = FrontPorchExtensions(tier: 'lite');
      await pumpAfterglowHost(
        tester,
        chat: _SeededGroup(
          [mara],
          GroupChat(
            id: _groupId,
            name: 'Pair',
            defaultMemberRealismState: _realismOn.defaultMemberJson,
          ),
        ),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(
        find.text(
          "Mara's Realism, Needs and Afterglow start when they are promoted "
          'to a full member of this group.',
        ),
        findsOneWidget,
      );
      expect(find.text('Short-Term Bond'), findsNothing);
      expect(find.text('Needs Simulation'), findsNothing);
      expect(find.text('Afterglow for Mara'), findsNothing);
      expect(find.text('Chaos Mode · Off in this chat'), findsOneWidget);
    });
  });

  testWidgets('a member editor hides Realism, Needs and Afterglow while '
      'Porch Life does not allow Realism, and keeps her settings', (
    tester,
  ) async {
    await tester.runAsync(() async {
      CharacterCard? saved;
      final mara = member()
        ..frontPorchExtensions = FrontPorchExtensions(needsPace: 'fast');
      await pumpAfterglowHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EditCharacterPage(
              character: mara,
              memberOfGroup: 'Pair',
              onSaveOverride: (c) async => saved = c,
              memberGroup: MemberGroupView(
                read: () => const GroupWideValues(
                  realism: true,
                  needs: true,
                  chaos: false,
                  afterglow: true,
                  timeOfDay: 'evening',
                  dayCount: 3,
                ),
                realismAllowed: false,
              ),
            ),
          ),
        ),
      );

      expect(
        find.text(
          'Realism, Needs and Afterglow are hidden: the Realism Engine is off '
          "in Porch Life. Mara's settings are kept.",
        ),
        findsOneWidget,
      );
      expect(find.text('Needs Simulation'), findsNothing);
      expect(find.text('Afterglow for Mara'), findsNothing);
      expect(
        find.text('Realism Verification (Director/Verifier)'),
        findsNothing,
      );
      expect(
        find.text(
          "Time & Day · this group's new chats start at: Evening, Day 3",
        ),
        findsOneWidget,
      );
      await saveTwiceFast(tester);
      expect(saved?.frontPorchExtensions?.needsPace, 'fast');
    });
  });

  testWidgets("a member's Director authority saves to her own row", (
    tester,
  ) async {
    await tester.runAsync(() async {
      final mara = member()..frontPorchExtensions = FrontPorchExtensions();
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], GroupChat(id: _groupId, name: 'Pair')),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(find.text('Director authority (needs)'), findsNothing);
      form(tester).onRealismVerificationChanged(true);
      await tester.pump();
      expect(find.text('Director authority (needs)'), findsOneWidget);
      form(tester).onNeedsDirectorAuthorityChanged!(true);
      await tester.pump();
      await saveTwiceFast(tester);

      final ext = rowExtensions(await memberRow());
      expect(ext?.realismVerificationEnabled, isTrue);
      expect(ext?.realismNeedsDirectorAuthority, isTrue);
    });
  });

  // ── Review round: the start never changes what else the group says ──

  /// Group Realism on with Needs off for new chats, seeded for Bo only:
  /// Mara joined later (Add character) and has no seed.
  final needsOff = buildGroupRealismBlobs(
    seeds: {
      'mem-bo': {...defaultGroupMemberRealismSeed()}..remove('needs'),
    },
    needsEnabled: false,
    timeOfDay: 'morning',
    dayCount: 1,
  );

  Future<void> openFromEditGroup(
    WidgetTester tester, {
    required String defaultMemberJson,
    required String baselineJson,
    void Function(bool toRealism)? done,
    void Function(String defaultMemberJson)? handed,
  }) => pumpHost(
    tester,
    chat: _OpenGroup(const []),
    onOpen: (context) async {
      final toRealism = await editGroupMemberFromEditGroup(
        context,
        group: GroupChat(id: _groupId, name: 'Pair'),
        member: member(),
        memberId: _memberId,
        defaultMemberJson: defaultMemberJson,
        baselineJson: baselineJson,
        settingId: null,
        inheritCharacterLorebooks: false,
        onStartSaved: (d, _) => handed?.call(d),
      );
      done?.call(toRealism);
    },
  );

  Future<void> storeBlobs(String defaultMemberJson, String baselineJson) =>
      db.updateGroup(
        GroupsCompanion(
          id: const Value(_groupId),
          defaultMemberRealismState: Value(defaultMemberJson),
          baselineRealismState: Value(baselineJson),
        ),
      );

  testWidgets("a member with no seed saving her start leaves a group's Needs "
      'off for new chats', (tester) async {
    await tester.runAsync(() async {
      await storeBlobs(needsOff.defaultMemberJson, needsOff.baselineJson);
      String? handed;
      await openFromEditGroup(
        tester,
        defaultMemberJson: needsOff.defaultMemberJson,
        baselineJson: needsOff.baselineJson,
        handed: (d) => handed = d,
      );
      form(tester).onTrustLevelChanged(70);
      await tester.pump();
      await saveTwiceFast(tester);

      final stored = (await db.getGroupById(_groupId))!;
      expect(
        parseGroupRealismSeeds(
          stored.defaultMemberRealismState,
        )[_memberId]!['trust'],
        70,
      );
      expect(
        groupTemplateRealismOf(stored.defaultMemberRealismState).needsOn,
        isFalse,
        reason: "THE BUG: her new seed's Needs bars switched Needs on",
      );
      expect(groupTemplateRealismOf(handed!).needsOn, isFalse);
    });
  });

  testWidgets("a seed an older group filed under the member's origin is the "
      'one her editor shows, and saving moves it onto her', (tester) async {
    await tester.runAsync(() async {
      await db.updateGroupMember(
        GroupMembersCompanion(
          id: const Value(_memberId),
          memberState: Value(
            GroupMember.encodeProvenance(originStableId: 'mara-origin'),
          ),
        ),
      );
      final legacy = buildGroupRealismBlobs(
        seeds: {
          'mara-origin': {
            ...defaultGroupMemberRealismSeed(),
            'affection': 90,
            'needs': {'hunger': 20},
          },
          'mem-bo': {
            ...defaultGroupMemberRealismSeed(),
            'relationships': {'mara-origin': 40},
          },
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await storeBlobs(legacy.defaultMemberJson, legacy.baselineJson);
      await openFromEditGroup(
        tester,
        defaultMemberJson: legacy.defaultMemberJson,
        baselineJson: legacy.baselineJson,
      );

      expect(
        form(tester).shortTermBond,
        90,
        reason: "THE BUG: the editor showed her card's values instead",
      );
      form(tester).onTrustLevelChanged(30);
      await tester.pump();
      await saveTwiceFast(tester);

      final stored = (await db.getGroupById(_groupId))!;
      final seeds = parseGroupRealismSeeds(stored.defaultMemberRealismState);
      expect(seeds.containsKey('mara-origin'), isFalse);
      expect(
        [seeds[_memberId]!['affection'], seeds[_memberId]!['trust']],
        [90, 30],
      );
      expect(seeds[_memberId]!['needs'], {
        'hunger': 20,
      }, reason: 'what the old seed held is kept');
      expect(seeds['mem-bo']!['relationships'], {_memberId: 40});
      expect(
        (jsonDecode(stored.baselineRealismState) as Map).containsKey(
          'mara-origin',
        ),
        isFalse,
      );
    });
  });

  // The guard the deleted Edit group member editor carried: Long-Term Bond
  // an old editor saved into trust reads back as Long-Term Bond, and the
  // next save un-mixes it.
  testWidgets('a start whose Long-Term Bond was saved into trust reads it '
      'back as Long-Term Bond and saves it un-mixed', (tester) async {
    await tester.runAsync(() async {
      final mixed = buildGroupRealismBlobs(
        seeds: {
          _memberId: {
            ...defaultGroupMemberRealismSeed(),
            'affection': 35,
            'trust': 250,
          },
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await storeBlobs(mixed.defaultMemberJson, mixed.baselineJson);
      await openFromEditGroup(
        tester,
        defaultMemberJson: mixed.defaultMemberJson,
        baselineJson: mixed.baselineJson,
      );

      expect((form(tester).longTermBond, form(tester).trustLevel), (250, 50));
      form(tester).onShortTermBondChanged(60);
      await tester.pump();
      await saveTwiceFast(tester);

      final seed = parseGroupRealismSeeds(
        (await db.getGroupById(_groupId))!.defaultMemberRealismState,
      )[_memberId]!;
      expect(
        [seed['affection'], seed['longTermScore'], seed['trust']],
        [60, 250, 50],
      );
    });
  });

  /// The open chat's copy of a group whose row is [defaultMemberJson], with
  /// a Group Settings → Needs edit not saved yet: "Enjoys low hygiene" for
  /// [who], which that tab files under the member even in a group whose new
  /// chats run without Realism (persistGroupMemberPref).
  GroupChat openWithUnsavedLowHygiene(String defaultMemberJson, String who) {
    final blob = defaultMemberJson == '{}'
        ? <String, dynamic>{'perChar': <String, dynamic>{}}
        : Map<String, dynamic>.from(jsonDecode(defaultMemberJson) as Map);
    final perChar = Map<String, dynamic>.from(blob['perChar'] as Map);
    perChar[who] = {
      ...?(perChar[who] as Map?)?.cast<String, dynamic>(),
      'enjoysLowHygiene': true,
    };
    blob['perChar'] = perChar;
    return GroupChat(
      id: _groupId,
      name: 'Pair',
      defaultMemberRealismState: jsonEncode(blob),
    );
  }

  testWidgets("a member's start saved while the open chat holds unsaved Group "
      "Settings edits writes only her start to the row", (tester) async {
    await tester.runAsync(() async {
      await seedGroupRow();
      final mara = member();
      final open = openWithUnsavedLowHygiene(
        _realismOn.defaultMemberJson,
        'mem-bo',
      );
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], open),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );
      form(tester).onTrustLevelChanged(-20);
      await tester.pump();
      await saveTwiceFast(tester);

      final row = parseGroupRealismSeeds(
        (await db.getGroupById(_groupId))!.defaultMemberRealismState,
      );
      expect(row[_memberId]!['trust'], -20);
      expect(
        row.containsKey('mem-bo'),
        isFalse,
        reason: "Group Settings' unsaved edit is not this editor's to save",
      );
      final live = parseGroupRealismSeeds(open.defaultMemberRealismState);
      expect(live[_memberId]!['trust'], -20, reason: "the open chat's copy");
      expect(live['mem-bo'], {'enjoysLowHygiene': true});
    });
  });

  testWidgets("the sidebar member editor shows this chat's Realism, and no "
      "start when the group's saved new chats run without it", (tester) async {
    await tester.runAsync(() async {
      // Edit group switched Realism off for new chats and saved while the
      // chat was open: the chat runs Realism, and its copy still has the
      // seeds until it reopens.
      final mara = member();
      final open = GroupChat(
        id: _groupId,
        name: 'Pair',
        defaultMemberRealismState: _realismOn.defaultMemberJson,
        baselineRealismState: _realismOn.baselineJson,
      );
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], open),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(
        find.text('Realism Engine · On in this chat'),
        findsOneWidget,
        reason: "the line is this chat's own switch, and says so",
      );
      expect(form(tester).showStartingState, isFalse);
      expect(
        find.text(
          "This group's new chats start without Realism, so there's no start "
          'to set. Set in Edit group → Realism & Dynamics.',
        ),
        findsOneWidget,
      );
      pickVoice(tester, 'af_heart');
      await tester.pump();
      await saveTwiceFast(tester);
      expect(
        (await db.getGroupById(_groupId))!.defaultMemberRealismState,
        '{}',
        reason: "Realism never comes back on for the group's new chats",
      );
      expect(
        open.defaultMemberRealismState,
        _realismOn.defaultMemberJson,
        reason: "the open chat's copy is left as it is",
      );
    });
  });

  // Every reader of the blob (New Chat, Edit group, Group Settings) has a
  // group whose only member entries carry no bonds run Realism; an older
  // editor's card-named keys are one such shape. The editor offered no
  // start there and so could never give one.
  testWidgets("a group whose only member entry has an older editor's keys "
      'offers a start and saves it', (tester) async {
    await tester.runAsync(() async {
      final legacy = jsonEncode({
        'perChar': {
          _memberId: {
            'shortTermBond': 80,
            'longTermBond': 60,
            'trustLevel': 20,
            'characterEmotion': 'shy',
          },
        },
      });
      await storeBlobs(legacy, '{}');
      final mara = member();
      await pumpHost(
        tester,
        chat: _SeededGroup(
          [mara],
          GroupChat(
            id: _groupId,
            name: 'Pair',
            defaultMemberRealismState: legacy,
          ),
        ),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(find.text('Realism Engine · On in this chat'), findsOneWidget);
      expect(form(tester).showStartingState, isTrue);
      form(tester).onTrustLevelChanged(30);
      await tester.pump();
      await saveTwiceFast(tester);

      final seed = parseGroupRealismSeeds(
        (await db.getGroupById(_groupId))!.defaultMemberRealismState,
      )[_memberId]!;
      expect(seed['trust'], 30);
      expect(seed.containsKey('affection'), isTrue);
      expect(
        seed.keys.where(legacyCardExtSeedKeys.contains),
        isEmpty,
        reason: 'the dead card-named copies are dropped',
      );
    });
  });

  testWidgets("a Group Settings preference in the open chat of a group whose "
      'new chats run without Realism offers no start and switches nothing '
      'on', (tester) async {
    await tester.runAsync(() async {
      // The row: new chats without Realism. The open chat: Needs → "Enjoys
      // low hygiene" for Mara, closed with X (not saved).
      final mara = member();
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], openWithUnsavedLowHygiene('{}', _memberId)),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );
      final offered = form(tester).showStartingState;
      form(tester).onShortTermBondChanged(90);
      await tester.pump();
      await saveTwiceFast(tester);

      final row = (await db.getGroupById(_groupId))!.defaultMemberRealismState;
      expect(
        groupTemplateRealismOf(row).realismOn,
        isFalse,
        reason: 'THE BUG: the row was written from the open copy',
      );
      expect(row, isNot(contains('enjoysLowHygiene')));
      expect(offered, isFalse, reason: 'no start where Realism does not run');
    });
  });

  testWidgets("Edit group's Realism & Dynamics link backed out of with Keep "
      'editing does not move the page later', (tester) async {
    await tester.runAsync(() async {
      bool? toRealism;
      await openFromEditGroup(
        tester,
        defaultMemberJson: _realismOn.defaultMemberJson,
        baselineJson: _realismOn.baselineJson,
        done: (v) => toRealism = v,
      );
      pickVoice(tester, 'af_heart');
      await tester.pump();
      final link = find.text('Realism & Dynamics ›').first;
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(EditCharacterPage), findsOneWidget);

      await saveTwiceFast(tester);
      await pumpUntil(tester, () => toRealism != null, why: 'never closed');
      expect(toRealism, isFalse, reason: 'THE BUG: Save jumped to the tab');
    });
  });

  testWidgets("Edit group's member editor says where Chaos and the lorebook "
      'really are set', (tester) async {
    await tester.runAsync(() async {
      await openFromEditGroup(
        tester,
        defaultMemberJson: _realismOn.defaultMemberJson,
        baselineJson: _realismOn.baselineJson,
      );
      final chaos = find.ancestor(
        of: find.text("Chaos Mode · Off for this group's new chats"),
        matching: find.byType(GroupWideLine),
      );
      expect(
        find.descendant(of: chaos, matching: find.byType(TextButton)),
        findsNothing,
        reason: 'no switch changes how new chats start Chaos',
      );
      expect(
        find.descendant(
          of: chaos,
          matching: find.text('the setting the group was made with'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Lorebook'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'when Edit group → Lore & Worlds has "Inherit character & world '
          'lorebooks" on',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Worlds'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'While Edit group → Lore & Worlds has "Inherit character & world '
          "lorebooks\" on, Mara's own worlds add their lore when Mara speaks",
        ),
        findsOneWidget,
      );
    });
  });

  // Porch Life's Realism permission off hides a member's Realism, Needs and
  // Afterglow in both editors (each way in reads it), keeping her settings.
  for (final way in ['the chat sidebar', 'Edit group']) {
    testWidgets("$way's member editor hides Realism while Porch Life does "
        'not allow it', (tester) async {
      await tester.runAsync(() async {
        await tester.binding.setSurfaceSize(const Size(1280, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await seedGroupRow();
        final mara = member();
        final chat = _SeededGroup(
          [mara],
          GroupChat(
            id: _groupId,
            name: 'Pair',
            defaultMemberRealismState: _realismOn.defaultMemberJson,
          ),
        );
        final library = _Library();
        final storage = FakeStorageService();
        final worlds = FakeWorldRepository();
        addTearDown(library.dispose);
        addTearDown(storage.dispose);
        addTearDown(worlds.dispose);
        addTearDown(chat.dispose);
        await storage.realismSettings.setRealismAllowed(false);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              ChangeNotifierProvider<CharacterRepository>.value(value: library),
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<WorldRepository>.value(value: worlds),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => way == 'Edit group'
                        ? editGroupMemberFromEditGroup(
                            context,
                            group: GroupChat(id: _groupId, name: 'Pair'),
                            member: member(),
                            memberId: _memberId,
                            defaultMemberJson: _realismOn.defaultMemberJson,
                            baselineJson: _realismOn.baselineJson,
                            settingId: null,
                            inheritCharacterLorebooks: false,
                            onStartSaved: (_, _) {},
                          )
                        : showEditCharacterDialog(context, mara),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await pumpUntil(
          tester,
          () => find.byType(EditCharacterPage).evaluate().isNotEmpty,
          why: 'the editor never opened',
        );

        expect(
          find.text(
            'Realism, Needs and Afterglow are hidden: the Realism Engine is '
            "off in Porch Life. Mara's settings are kept.",
          ),
          findsOneWidget,
        );
        expect(find.text('Short-Term Bond'), findsNothing);
        expect(find.text('Needs Simulation'), findsNothing);
      });
    });
  }

  // Opening a member's editor from the chat reads the group's row first. A
  // second tap while it read opened a second editor, and a read that threw
  // left the tap doing nothing, with no word why.
  group("opening a member's editor from the chat", () {
    Future<void> pumpOpener(WidgetTester tester, AppDatabase database) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mara = member();
      final chat = _SeededGroup([mara], GroupChat(id: _groupId, name: 'Pair'));
      final library = _Library();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      addTearDown(library.dispose);
      addTearDown(storage.dispose);
      addTearDown(worlds.dispose);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: database),
            ChangeNotifierProvider<CharacterRepository>.value(value: library),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showEditCharacterDialog(context, mara),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      await pumpUntil(
        tester,
        () => find.byType(EditCharacterPage).evaluate().isNotEmpty,
        why: 'the editor never opened',
      );
      // Let a second read (if any) land and its dialog open.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a double tap opens one editor', (tester) async {
      await tester.runAsync(seedGroupRow);
      await pumpOpener(tester, db);
      // A slow disk: the group's read waits behind a transaction, so the
      // second tap lands while the first read is still in flight.
      final release = Completer<void>();
      late Future<void> held;
      await tester.runAsync(() async {
        held = db.transaction(() => release.future);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await doubleTapNoFrame(tester, find.text('Open'));
      release.complete();
      await tester.runAsync(() async {
        await held;
        await settle(tester);
      });
      expect(find.byType(EditCharacterPage), findsOneWidget);
    });

    testWidgets("a group read that fails still opens her editor, offering no "
        'start, and says so', (tester) async {
      await tester.runAsync(() async {
        final broken = AppDatabase.forTesting(sameIsolate: true);
        addTearDown(broken.close);
        await broken.customStatement('DROP TABLE groups');
        await pumpOpener(tester, broken);
        await tester.tap(find.text('Open'));
        await settle(tester);
        expect(
          find.text(
            "Couldn't read this group's settings, so where the member starts "
            'is not shown.',
          ),
          findsWidgets,
          reason: 'the messenger shows it on every Scaffold, the editor too',
        );
        expect(form(tester).showStartingState, isFalse);
      });
    });
  });

  // New Chat seeds a group's Chaos as its own setting OR Porch Life's Chaos
  // default, and its Needs only while Porch Life runs Needs. The lines for
  // new chats showed the group's flags alone, and named Group Settings as
  // where Chaos is set, though its switch changes that chat only.
  group("Edit group's lines for new chats follow Porch Life", () {
    Future<void> openWith(
      WidgetTester tester,
      Future<void> Function(FakeStorageService storage) porchLife,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final chat = _OpenGroup(const []);
      final library = _Library();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      addTearDown(library.dispose);
      addTearDown(storage.dispose);
      addTearDown(worlds.dispose);
      addTearDown(chat.dispose);
      await porchLife(storage);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<CharacterRepository>.value(value: library),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => editGroupMemberFromEditGroup(
                    context,
                    group: GroupChat(id: _groupId, name: 'Pair'),
                    member: member(),
                    memberId: _memberId,
                    defaultMemberJson: _realismOn.defaultMemberJson,
                    baselineJson: _realismOn.baselineJson,
                    settingId: null,
                    inheritCharacterLorebooks: false,
                    onStartSaved: (_, _) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await pumpUntil(
        tester,
        () => find.byType(EditCharacterPage).evaluate().isNotEmpty,
        why: 'the editor never opened',
      );
    }

    testWidgets("Chaos is on for new chats while Porch Life's default is, and "
        'says so', (tester) async {
      await tester.runAsync(() async {
        await openWith(
          tester,
          (s) => s.realismSettings.setChaosModeDefault(true),
        );
        final chaos = find.ancestor(
          of: find.text("Chaos Mode · On for this group's new chats"),
          matching: find.byType(GroupWideLine),
        );
        expect(chaos, findsOneWidget, reason: 'the group was made without it');
        expect(
          find.descendant(
            of: chaos,
            matching: find.text("on because Porch Life's Chaos default is on"),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets("Needs is off for new chats while Porch Life runs no Needs, "
        "with the Needs switches' note", (tester) async {
      await tester.runAsync(() async {
        await openWith(
          tester,
          (s) => s.realismSettings.setNeedsSimDefault(false),
        );
        final needs = find.ancestor(
          of: find.text("Needs · Off for this group's new chats"),
          matching: find.byType(GroupWideLine),
        );
        expect(needs, findsOneWidget, reason: 'the group chose Needs on');
        expect(
          find.descendant(
            of: needs,
            matching: find.text(
              "Off in Porch Life, so no chat runs Needs. This group's choice "
              'for new chats is kept.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: needs, matching: find.byType(TextButton)),
          findsNothing,
          reason: "the group's own Needs switch is greyed",
        );
      });
    });
  });
}

/// An open group named Pair that records each member Afterglow it sets. Like
/// ChatService's, its setter does nothing when the card already holds [on].
class _AfterglowGroup extends _OpenGroup {
  _AfterglowGroup(super.members);

  final afterglowSets = <(CharacterCard, bool)>[];

  @override
  GroupChat? get activeGroup => GroupChat(id: _groupId, name: 'Pair');

  @override
  Future<void> setMemberAfterglowEnabled(CharacterCard member, bool on) async {
    if ((member.frontPorchExtensions?.afterglowEnabled ?? true) == on) return;
    afterglowSets.add((member, on));
    member.frontPorchExtensions =
        (member.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
          afterglowEnabled: on,
        );
  }
}

/// Group Realism on, with Afterglow for new chats, as Edit group loads it.
final _realismOn = buildGroupRealismBlobs(
  seeds: {_memberId: defaultGroupMemberRealismSeed()},
  needsEnabled: true,
  timeOfDay: 'morning',
  dayCount: 1,
);

/// An open group named Pair whose definition is [group] (its realism blobs
/// are the ones the editor reads and saves into).
class _SeededGroup extends _OpenGroup {
  _SeededGroup(super.members, this.group);

  final GroupChat group;

  @override
  GroupChat? get activeGroup => group;
}
