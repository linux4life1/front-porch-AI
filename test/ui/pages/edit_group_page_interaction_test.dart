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

// Edit Group page interaction net — required by the provability rule BEFORE
// edit_group_page.dart is split. NOTHING covered this page: no golden (not
// even an empty state), no E2E (group suites drive group CHAT; the create
// wizard is a separate page). Walks all four real tabs, edits real fields,
// flips the inherit switch, and saves — asserting the round-trip through
// the repo (name + stableId + the flipped flag).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// The shared fake throws on unknown members; the save path calls
/// [save] — record it so the round-trip is assertable.
class _RecordingGroups extends FakeGroupChatRepository {
  GroupChat? saved;
  @override
  Future<void> save(GroupChat group) async {
    saved = group;
  }

  @override
  Future<List<GroupMember>> getMembersForGroup(String groupId) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all four tabs render, take edits, and Save round-trips', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final group = GroupChat(
      id: 'g1',
      name: 'Porch Regulars',
      stableId: 'Porch_Regulars_123',
      systemPrompt: 'Keep it cozy.',
      firstMessage: 'Evening, all.',
      // Starts on so the tab's flip below is a real change (new groups
      // default to off).
      inheritCharacterLorebooks: true,
    );

    final groups = _RecordingGroups();
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    final characters = FakeCharacterRepository([]);
    final database = db.AppDatabase.forTesting();
    for (final s in [groups, chat, storage, worlds, characters]) {
      addTearDown(s.dispose);
    }
    // Deliberately NOT closed: drift's close wall-hangs under testWidgets
    // (same class of hang as seeding — see story_reader net history), and
    // the handle is never opened (only _editMember touches it, on tap).
    // An unopened in-memory db leaking at process exit is harmless.

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<CharacterRepository>.value(value: characters),
          Provider<db.AppDatabase>.value(value: database),
        ],
        child: MaterialApp(home: EditGroupPage(group: group)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // ── Details tab (details part): edit the name ─────────────────────────
    expect(find.text('Porch Regulars'), findsWidgets,
        reason: 'Details tab must show the seeded group name');
    // The name field is the Details tab's first text input.
    await tester.enterText(
      find.byType(EditableText).first,
      'Porch Regulars (Renamed)',
    );
    await tester.pump(const Duration(milliseconds: 200));

    // ── Dialogue tab (dialogue part) ──────────────────────────────────────
    await tester.tap(find.text('Dialogue'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('First Message'), findsWidgets,
        reason: 'Dialogue tab landmark did not render');

    // ── Lore & Worlds tab (lore_worlds part): add an entry + flip inherit ─
    await tester.tap(find.text('Lore & Worlds'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Add Entry'));
    expect(find.text('Add Entry'), findsWidgets,
        reason: 'Lore & Worlds landmark (its future part) did not render');

    final inherit = find.byType(SwitchListTile).first;
    await tester.ensureVisible(inherit);
    await tester.tap(inherit);
    await tester.pump(const Duration(milliseconds: 200));

    // ── Realism tab (stays in shell) ──────────────────────────────────────
    await tester.tap(find.text('Realism & Dynamics'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // ── Save: the repo must receive the edited group, stableId intact ─────
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(groups.saved, isNotNull, reason: 'Save must reach the repository');
    expect(groups.saved!.name, 'Porch Regulars (Renamed)');
    expect(groups.saved!.stableId, 'Porch_Regulars_123',
        reason: 'the portable stable id must survive an edit round-trip');
    expect(groups.saved!.inheritCharacterLorebooks, isFalse,
        reason: 'the inherit toggle flip (lore part) must round-trip '
            'through Save — proves a cross-part edit reaches the model');
  });
}
