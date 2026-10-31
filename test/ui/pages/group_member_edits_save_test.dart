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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
import 'package:front_porch_ai/ui/pages/edit_group/edit_group.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

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

  testWidgets("Edit group's Realism tab saves each member's Recovery block "
      "to the member's row, while Porch Life allows Afterglow", (tester) async {
    await tester.runAsync(() async {
      final storage = FakeStorageService();
      final chat = _OpenGroup(const []);
      addTearDown(storage.dispose);
      addTearDown(chat.dispose);
      final mara = member();
      Future<void> pumpTab() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<AppDatabase>.value(value: db),
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<StorageService>.value(value: storage),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EditGroupRealismTab(
                  key: UniqueKey(),
                  loaded: true,
                  members: const [],
                  defaultMemberJson: _realismOn.defaultMemberJson,
                  baselineJson: _realismOn.baselineJson,
                  onChanged: (_, _) {},
                  memberCards: [mara],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pumpTab();
      expect(find.byType(RecoveryBlock), findsNothing, reason: 'not allowed');

      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      await pumpTab();
      tester
          .widget<RecoveryBlock>(find.byType(RecoveryBlock))
          .onChanged(RecoveryProfile.auto.withMinutes(60));
      int? minutes;
      for (var i = 0; i < 100 && minutes != 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final raw = (await memberRow()).frontPorchExtensions;
        minutes = raw == null
            ? null
            : FrontPorchExtensions.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              ).recovery.recoveryMinutes;
      }
      expect(minutes, 60, reason: "the change reached Mara's row");
    });
  });

  testWidgets("Edit group's Recovery block writes only Recovery, onto the "
      "open chat's own member, and skips a member switched off", (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Since Edit group loaded Mara, Group Settings switched her own
      // Afterglow off: her row and the open chat's copy say off.
      final off = FrontPorchExtensions(afterglowEnabled: false);
      await db.updateGroupMember(
        GroupMembersCompanion(
          id: const Value(_memberId),
          frontPorchExtensions: Value(jsonEncode(off.toJson())),
        ),
      );
      final live = member()..frontPorchExtensions = off;
      final loaded = member()..frontPorchExtensions = FrontPorchExtensions();
      final shy = CharacterCard(name: 'Shy')
        ..dbId = 'mem-shy'
        ..frontPorchExtensions = FrontPorchExtensions(afterglowEnabled: false);
      final storage = FakeStorageService();
      final chat = _OpenGroup([live]);
      addTearDown(storage.dispose);
      addTearDown(chat.dispose);
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<StorageService>.value(value: storage),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditGroupRealismTab(
                loaded: true,
                members: const [],
                defaultMemberJson: _realismOn.defaultMemberJson,
                baselineJson: _realismOn.baselineJson,
                onChanged: (_, _) {},
                memberCards: [loaded, shy],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byType(RecoveryBlock),
        findsOneWidget,
        reason: "Shy's own switch is off",
      );

      tester
          .widget<RecoveryBlock>(find.byType(RecoveryBlock))
          .onChanged(RecoveryProfile.auto.withMinutes(60));
      FrontPorchExtensions? row;
      for (var i = 0; i < 100 && row?.recovery.recoveryMinutes != 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final raw = (await memberRow()).frontPorchExtensions;
        row = raw == null
            ? null
            : FrontPorchExtensions.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              );
      }
      expect(row?.recovery.recoveryMinutes, 60);
      expect(
        row?.afterglowEnabled,
        isFalse,
        reason: "the page's older copy did not write her switch back on",
      );
      expect(live.frontPorchExtensions?.recovery.recoveryMinutes, 60);
      expect(live.frontPorchExtensions?.afterglowEnabled, isFalse);
      expect(chat.refreshed, [same(live)], reason: "the chat's own member");
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
