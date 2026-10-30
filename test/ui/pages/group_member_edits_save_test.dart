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
//   re-keyed memories filed under the character's bare name.
// - UI Settings from a group's sidebar (chat colours, avatar lock) did the
//   same through the library repository.
// - Edit group's per-member Edit showed Voice and the greeting seeds and
//   saved neither.
//
// Red proofs: drop the member branch in showEditCharacterDialog (test 1), in
// UiSettingsDialog._updateCharacterExtension (test 3), put back Edit group's
// content-only write (test 4, voice) or drop the Realism-hidden seed branch
// in EditCharacterCardWriter.writeFields (test 4, seed).

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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

const _groupId = 'grp-edits';
const _memberId = 'mem-mara';

/// A group chat open on [_members]. Records the roster refresh a save asks
/// for instead of running ChatService's.
class _OpenGroup extends FakeChatService {
  _OpenGroup(this._members);

  final List<CharacterCard> _members;
  final refreshed = <CharacterCard>[];

  @override
  bool get isGroupMode => _members.isNotEmpty;

  @override
  List<CharacterCard> get groupCharacters => _members;

  @override
  void refreshActiveCharacterCard(CharacterCard card) => refreshed.add(card);
}

/// The library. The Details tab asks it for a cover; the shared fake throws
/// for cards it does not hold. (`updateCharacter` is an extension, so a
/// test double cannot record it: the member's row is the evidence.)
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
        alternateGreetings: Value(jsonEncode(['You came back.'])),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<GroupMemberRow> memberRow() async =>
      (await db.getGroupMembers(_groupId)).single;

  CharacterCard member() => CharacterCard(
    name: 'Mara',
    description: 'Keeps the lighthouse.',
    alternateGreetings: ['You came back.'],
  )..dbId = _memberId;

  Future<void> pumpHost(
    WidgetTester tester, {
    required ChatService chat,
    required _Library library,
    required void Function(BuildContext) onOpen,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    addTearDown(storage.dispose);
    addTearDown(worlds.dispose);
    addTearDown(library.dispose);
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

  /// Taps Save and lets the save's real async work finish: under runAsync,
  /// pumpAndSettle returns as soon as no frame is scheduled, before the
  /// awaited writes behind Save have run.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pickVoiceAndSave(WidgetTester tester, String voice) async {
    tester
        .widget<CharacterVoicePicker>(find.byType(CharacterVoicePicker))
        .onChanged(voice);
    await tester.pump();
    await save(tester);
  }

  testWidgets('Edit Character on a group member saves to the member\'s row, '
      'never the library', (tester) async {
    await tester.runAsync(() async {
      final mara = member();
      final chat = _OpenGroup([mara]);
      final library = _Library();
      await pumpHost(
        tester,
        chat: chat,
        library: library,
        onOpen: (context) => showEditCharacterDialog(context, mara),
      );

      await pickVoiceAndSave(tester, 'af_heart');

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

  testWidgets('Edit Character on a 1:1 character keeps the library save and '
      'the portrait picker', (tester) async {
    await tester.runAsync(() async {
      final wren = CharacterCard(name: 'Wren', description: 'x')
        ..dbId = 'char-wren';
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        library: _Library(),
        onOpen: (context) => showEditCharacterDialog(context, wren),
      );

      final page = tester.widget<EditCharacterPage>(
        find.byType(EditCharacterPage),
      );
      expect(page.onSaveOverride, isNull, reason: 'no member row to write');
      expect(page.allowAvatarChange, isTrue);
    });
  });

  testWidgets('UI Settings on a group member saves to the member\'s row, '
      'never the library', (tester) async {
    await tester.runAsync(() async {
      final mara = member();
      final chat = _OpenGroup([mara]);
      final library = _Library();
      await pumpHost(
        tester,
        chat: chat,
        library: library,
        onOpen: (context) => showDialog<void>(
          context: context,
          builder: (_) => UiSettingsDialog(character: mara),
        ),
      );

      tester
          .widget<AvatarLockToggle>(find.byType(AvatarLockToggle))
          .onChanged(true);
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }

      final json = (await memberRow()).frontPorchExtensions;
      expect(json, isNotNull, reason: 'the lock never reached the row');
      final ext = FrontPorchExtensions.fromJson(
        jsonDecode(json!) as Map<String, dynamic>,
      );
      expect(ext.avatarLocked, isTrue);
      expect(chat.refreshed.single.frontPorchExtensions?.avatarLocked, isTrue);
    });
  });

  testWidgets('Edit group\'s member Edit saves the voice and the greeting '
      'seeds it shows', (tester) async {
    await tester.runAsync(() async {
      await pumpHost(
        tester,
        chat: _OpenGroup(const []),
        library: _Library(),
        onOpen: (context) => editGroupMemberCard(context, member(), _memberId),
      );

      tester
          .widget<CharacterVoicePicker>(find.byType(CharacterVoicePicker))
          .onChanged('af_heart');
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
}
