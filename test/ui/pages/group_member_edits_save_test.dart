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
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
    show GroupMemberMode;
import 'package:front_porch_ai/ui/pages/edit_group/edit_group.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker/group_worlds_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart'
    show RealismTimeDayCard;
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_optional_features_card.dart'
    show RealismVerificationControls;
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/double_tap.dart';

const _groupId = 'grp-edits';

/// Member mode for a group named [name], with nothing of its own to save.
GroupMemberMode _mode(String name) => GroupMemberMode(
  groupName: name,
  memberId: _memberId,
  others: const [],
  scene: const GroupSceneTime(),
  values: const GroupMemberValues(),
  saveValues: (_) async {},
);
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
          mode: _mode('Pair'),
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
          mode: _mode('Pair'),
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
          mode: _mode('Pair'),
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

  testWidgets("the chat sidebar's member Edit sets a changed Afterglow "
      'through the chat, which clears her Lust', (tester) async {
    await tester.runAsync(() async {
      final mara = member()
        ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true);
      final chat = _AfterglowGroup([mara]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      expect(
        find.textContaining("You're editing Mara in Pair only."),
        findsOneWidget,
      );
      tester.widget<Switch>(afterglowSwitch('Afterglow')).onChanged!(false);
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
      final live = member()
        ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true);
      final chat = _AfterglowGroup([live]);
      await pumpAfterglowHost(
        tester,
        chat: chat,
        // Edit group's own copy, loaded from the row, not the chat's.
        onOpen: (context) => editGroupMemberCard(
          context,
          member()
            ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true),
          _memberId,
          mode: _mode('Pair'),
        ),
      );

      tester.widget<Switch>(afterglowSwitch('Afterglow')).onChanged!(false);
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
      final off = FrontPorchExtensions(
        afterglowEnabled: false,
        realismEnabled: true,
      );
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
          member()
            ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true),
          _memberId,
          mode: _mode('Pair'),
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
          mode: _mode('Pair'),
        ),
      );

      tester
          .widget<RealismFormSection>(find.byType(RealismFormSection))
          .onEnabledChanged(true);
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

      tester
          .widget<RealismFormSection>(find.byType(RealismFormSection))
          .onEnabledChanged(true);
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
      final off = FrontPorchExtensions(
        afterglowEnabled: false,
        realismEnabled: true,
      );
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
          mode: _mode('Pair'),
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

  testWidgets("a member's Realism Verification is the group's: greyed out, "
      'and Save is the 1:1 Save', (tester) async {
    await tester.runAsync(() async {
      final mara = member()
        ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true);
      await pumpHost(
        tester,
        chat: _SeededGroup([mara], GroupChat(id: _groupId, name: 'Pair')),
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );
      final verification = find.ancestor(
        of: find.byType(RealismVerificationControls),
        matching: find.byType(GreyedOut),
      );
      expect(verification, findsOneWidget);
      expect(
        tester.widget<GreyedOut>(verification).tooltip,
        'Realism Verification is set per group, not per character.',
      );
    });
  });

  // ── PR 5: one editor. Member mode adds the notice and "In the group" and
  // greys out what the group owns; the 1:1 editor names the groups its
  // character is in. ──

  testWidgets('member mode adds the notice and the group section and greys '
      'out Time & Day, Worlds and Chaos Mode', (tester) async {
    await tester.runAsync(() async {
      final mara = member()
        ..frontPorchExtensions = FrontPorchExtensions(realismEnabled: true);
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          mara,
          _memberId,
          mode: GroupMemberMode(
            groupName: 'Pair',
            memberId: _memberId,
            others: const [GroupMemberRef('mem-bo', 'Bo')],
            scene: const GroupSceneTime(timeOfDay: 'evening', dayCount: 3),
            values: const GroupMemberValues(),
            saveValues: (_) async {},
          ),
        ),
      );

      expect(
        find.textContaining("You're editing Mara in Pair only."),
        findsOneWidget,
      );
      expect(find.text('In Pair'), findsOneWidget);
      expect(find.text('Toward Bo · ', findRichText: true), findsNothing);
      // Time & Day, Chaos Mode and the Worlds tab are present but greyed.
      final greyed = tester
          .widgetList<GreyedOut>(find.byType(GreyedOut))
          .map((g) => g.tooltip)
          .toSet();
      expect(greyed, {
        'Time & Day is set per group, not per character.',
        'Chaos Mode is set per group for now.',
        'Realism Verification is set per group, not per character.',
        'Worlds are set per group, not per character.',
      });
      expect(find.text('Time of Day'), findsOneWidget);
      expect(find.text('Worlds'), findsOneWidget);
      // The 1:1 read-only lines and the old banner are gone.
      expect(find.byKey(const Key('group-member-editor-banner')), findsNothing);
      expect(find.textContaining('Group Settings'), findsNothing);
      expect(find.text('Enable Realism Engine'), findsOneWidget);
      // Save is the 1:1 Save, not the update flow's arrow.
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  testWidgets("In the group: a member's system prompt, note, strength and "
      'feeling are saved to the group store once, and Edit group holds the '
      'same values', (tester) async {
    await tester.runAsync(() async {
      final saved = <GroupMemberValues>[];
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          mode: GroupMemberMode(
            groupName: 'Pair',
            memberId: _memberId,
            others: const [GroupMemberRef('mem-bo', 'Bo')],
            scene: const GroupSceneTime(),
            values: const GroupMemberValues(),
            saveValues: (v) async => saved.add(v),
          ),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('group-member-system-prompt')),
      );
      await tester.enterText(
        find.byKey(const Key('group-member-system-prompt')),
        'Mara notices everything.',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('group-member-note')),
        'Keep it short.',
      );
      await tester.pump();
      tester
          .widget<Slider>(find.byKey(const Key('group-member-strength')))
          .onChanged!(7);
      await tester.pump();
      tester
          .widget<Slider>(find.byKey(const Key('group-member-feeling-mem-bo')))
          .onChanged!(120);
      await tester.pump();
      await doubleTapNoFrame(tester, find.text('Save'));
      await pumpUntil(
        tester,
        () => find.byType(EditCharacterPage).evaluate().isEmpty,
        why: 'Save never closed the editor',
      );
      expect(saved, hasLength(1), reason: 'the group store was written once');
      expect(saved.single.systemPrompt, 'Mara notices everything.');
      expect((saved.single.note, saved.single.strength), ('Keep it short.', 7));
      expect(saved.single.feelings, {'mem-bo': 120});

      // Edit group holds the very same store.
      final group = GroupChat(id: _groupId, name: 'Pair');
      applyGroupMemberValues(group, _memberId, saved.single);
      expect(groupMemberValuesOf(group, _memberId), saved.single);
      final draft = EditGroupDraft(group);
      addTearDown(draft.dispose);
      expect(draft.promptOf(_memberId).text, 'Mara notices everything.');
      expect(draft.noteOf(_memberId).text, 'Keep it short.');
      expect(draft.strengthOf(_memberId), 7);
      expect(draft.feelings[_memberId]?['mem-bo'], 120);
    });
  });

  testWidgets('a greyed Time & Day cannot be changed and says why on '
      'long-press', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member()..frontPorchExtensions = FrontPorchExtensions(),
          _memberId,
          mode: _mode('Pair'),
        ),
      );
      await tester.ensureVisible(find.byType(RealismTimeDayCard));
      await tester.pump();
      final dayField = find.descendant(
        of: find.byType(RealismTimeDayCard),
        matching: find.byType(EditableText),
      );
      await tester.enterText(dayField, '9');
      await tester.pump();
      expect(
        tester
            .widget<RealismFormSection>(find.byType(RealismFormSection))
            .dayCount,
        1,
        reason: 'the group owns the day number',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(
          find.ancestor(
            of: find.byType(RealismTimeDayCard),
            matching: find.byType(GreyedOut),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        find.text(
          'Time & Day is set per group, not per character.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('the Worlds tab of a member cannot be opened', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) => editGroupMemberCard(
          context,
          member(),
          _memberId,
          mode: _mode('Pair'),
        ),
      );
      await tester.tap(find.text('Worlds'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(GroupWorldsSection), findsNothing);
    });
  });

  testWidgets("a member's Save writes the group's copy once and leaves the "
      'library row alone', (tester) async {
    await tester.runAsync(() async {
      await db
          .into(db.characters)
          .insert(CharactersCompanion.insert(id: 'lib-mara', name: 'Mara'));
      final mara = member();
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        onOpen: (context) =>
            editGroupMemberCard(context, mara, _memberId, mode: _mode('Pair')),
      );
      var memberWrites = 0;
      final sub = db
          .tableUpdates(TableUpdateQuery.onTable(db.groupMembers))
          .listen((_) => memberWrites++);
      addTearDown(sub.cancel);
      await tester.enterText(
        find.widgetWithText(TextField, 'Keeps the lighthouse.'),
        'Keeps the lamp.',
      );
      await tester.pump();
      await doubleTapNoFrame(tester, find.text('Save'));
      await pumpUntil(
        tester,
        () => find.byType(EditCharacterPage).evaluate().isEmpty,
        why: 'Save never closed the editor',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((await memberRow()).description, 'Keeps the lamp.');
      expect(memberWrites, 1, reason: 'a double tap wrote the row twice');
      final library = await db.select(db.characters).getSingle();
      expect(library.description, isNot('Keeps the lamp.'));
    });
  });

  group('the 1:1 editor names the groups its character is in', () {
    Future<void> open(WidgetTester tester) => pumpHost(
      tester,
      chat: _OpenGroup(const []),
      onOpen: (context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EditCharacterPage(
            character: CharacterCard(name: 'Mara')..dbId = 'lib-mara',
          ),
        ),
      ),
    );

    testWidgets('a character in a group gets the line', (tester) async {
      await tester.runAsync(() async {
        await db.updateGroupMember(
          GroupMembersCompanion(
            id: const Value(_memberId),
            memberState: Value(
              GroupMember.encodeProvenance(
                originStableId: 'Mara',
                originLibraryDbId: 'lib-mara',
              ),
            ),
          ),
        );
        await db.updateGroup(
          const GroupsCompanion(
            id: Value(_groupId),
            name: Value('The Porch Trio'),
          ),
        );
        await open(tester);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
        expect(
          find.text(
            'Mara is also in The Porch Trio. Groups keep their own copy; '
            "changes here don't reach them.",
            findRichText: true,
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('a character in no group gets no line', (tester) async {
      await tester.runAsync(() async {
        await open(tester);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
        expect(find.byKey(const Key('character-in-groups-note')), findsNothing);
        expect(find.byKey(const Key('group-member-notice')), findsNothing);
      });
    });
  });

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
  });

  // A group has no host for your bubbles (bubbleHost), so a member's own
  // User Bubble and User Text colours are saved but never shown there. UI
  // Settings says so on a member, only while no chat theme is active (a
  // theme's colours do reach a group), and never in a 1:1. Red proof: drop
  // the note, or its theme condition, in ui_settings_dialog.dart.
  testWidgets("UI Settings on a group member says a group's bubbles use your "
      'own colours', (tester) async {
    final mara = member();
    await pumpHost(
      tester,
      chat: _OpenGroup([mara]),
      onOpen: (context) => showDialog<void>(
        context: context,
        builder: (_) => UiSettingsDialog(character: mara),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('AI Bubble').first,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.text('In a group, your bubbles use your own colours from Settings.'),
      findsOneWidget,
    );
  });

  testWidgets('UI Settings on a group member drops the note while a chat '
      "theme is active: the theme's colours reach the group", (tester) async {
    final mara = member();
    await pumpHost(
      tester,
      chat: _OpenGroup([mara]),
      onOpen: (context) => showDialog<void>(
        context: context,
        builder: (_) => UiSettingsDialog(
          character: mara,
          themeOverrides: ChatThemeOverrides(themeId: 'fantasy'),
          onThemeOverrides: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('AI Bubble').first,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('group-user-colours-note')), findsNothing);
  });

  testWidgets('UI Settings in a 1:1 has no group colours note', (tester) async {
    final mara = member();
    await pumpHost(
      tester,
      chat: FakeChatService(activeCharacter: mara),
      onOpen: (context) => showDialog<void>(
        context: context,
        builder: (_) => UiSettingsDialog(character: mara),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('AI Bubble').first,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('group-user-colours-note')), findsNothing);
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
