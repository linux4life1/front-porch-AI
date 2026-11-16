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

@Tags(['golden'])
@TestOn('linux')
library;

// ONE UI, in pixels. The desktop 1:1 Character State is the baseline; a group
// shows the same controls in the same places for the tapped member, so the
// group golden must look like the 1:1 one. Both are fed the same values
// (bonds, trust, fixation, needs, story clock) and the same Porch Life
// switches. The member with Realism off, the member with Needs off, and Group
// Dynamics (the one group-only section) follow. The structural twin of this
// file, which fails on a reorder with no pixels, is
// test/hygiene/one_ui_parity_test.dart.
//
// Every case runs on a REAL ChatService over an in-memory database, booted the
// way test/ui/chat_components/group_member_switches_sidebar_test.dart does.
// The shared timer-free FakeChatService does not fit here: it reports the
// Pockets feature off and renders no Needs bars, so a 1:1 baseline built on it
// would differ from a real group member for reasons that are the fake's, not
// the sidebar's, and the golden would pin the wrong baseline.
// Baselines regenerate on the Linux CI image (Update Goldens workflow).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/group_dynamics_section.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../helpers/chat_db_teardown.dart';
import '../support/creator_test_support.dart';
import '../support/golden_app.dart';

const _group = 'group_sidebar_parity';
const _surface = Size(380, 900);

/// The values both modes show, so the two goldens can be read side by side.
/// Needs are the engine's own defaults in both (a 1:1 chat and a new group
/// member start from them), so no snapshot is forced on either side.
const _shortTerm = 120;
const _longTerm = 60;
const _trust = 40;
const _fixation = 'the lighthouse logs';

/// Fixed story clock (never the wall clock): the FakeChatService anchors on
/// 2026-06-30, evening, day 3; the group is seeded to the same.
const _storyDate = '2026-06-30';

/// A StorageService with Porch Life's adult themes and Afterglow on, so the
/// Afterglow line shows in both modes, and Pockets on.
Future<StorageService> _storage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'realism_default': true,
    'needs_sim_default': true,
  });
  // Built inside runAsync: its init does real file I/O, which never
  // completes if it starts under the test's fake clock.
  final storage = (await tester.runAsync(() async {
    final s = StorageService();
    await s.initialized;
    await s.realismSettings.setAdultThemesEnabled(true);
    await s.realismSettings.setNsfwCooldownDefault(true);
    await s.realismSettings.setPocketsEnabled(true);
    return s;
  }))!;
  addTearDown(storage.dispose);
  return storage;
}

Widget _host(StorageService storage, ChatService chat, Widget child) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<ChatService>.value(value: chat),
      ],
      child: SizedBox(width: 340, child: child),
    );

/// A real 1:1 chat with Ana, seeded with the values every golden here shows.
Future<_GroupChat> _bootOneToOne(StorageService storage) async {
  final db = AppDatabase.forTesting(sameIsolate: true);
  final chat = _newChat(storage, db);
  final ana = CharacterCard(
    name: 'Ana',
    description: 'Keeps the porch.',
    firstMessage: 'Evening.',
    imagePath: p.join(Directory.systemTemp.path, 'Ana-parity-golden.png'),
  );
  await CharacterRepository(db, storage).addCharacter(ana);
  await chat.setActiveCharacter(ana);
  await chat.setRealismEnabled(true);
  await chat.setNeedsSimEnabled(true);
  await chat.setAfterglowEnabled(true);
  chat.relationshipService.loadScalars(
    affectionScore: _shortTerm,
    longTermScore: _longTerm,
    trustLevel: _trust,
    activeFixation: _fixation,
    fixationLifespan: 3,
  );
  chat.timeService.seedFromV2OrExt(
    timeOfDay: 'evening',
    dayCount: 3,
    storyStartDate: _storyDate,
  );
  return _GroupChat(db, chat);
}

ChatService _newChat(StorageService storage, AppDatabase db) =>
    ChatService(
        KoboldService(storage),
        UserPersonaService(db),
        storage,
        WorldRepository(storage, db),
      )
      ..setDatabase(db)
      ..setCharacterRepository(CharacterRepository(db, storage));

/// A real chat on an in-memory database: the 1:1 baseline, or a group whose
/// members are all seeded with the 1:1 baseline's values.
class _GroupChat {
  _GroupChat(this.db, this.chat);

  final AppDatabase db;
  final ChatService chat;

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  String idOf(String name) => chat.characterIdFor(member(name));

  static Future<_GroupChat> boot(
    StorageService storage,
    List<String> names,
  ) async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    final chat = _newChat(storage, db);
    final ids = [for (final n in names) 'mem-${n.toLowerCase()}'];
    Map<String, dynamic> seed(String id) {
      final s = defaultGroupMemberRealismSeed();
      s['affection'] = _shortTerm;
      s['longTermScore'] = _longTerm;
      s['trust'] = _trust;
      s['fixation'] = _fixation;
      s['fixationLifespan'] = 3;
      // Ana feels warmly about the others, so Group Dynamics has bars to
      // show; the rest are neutral.
      s['relationships'] = <String, int>{
        for (final other in ids)
          if (other != id) other: id == ids.first ? 150 : 20,
      };
      return s;
    }

    final blobs = buildGroupRealismBlobs(
      seeds: {for (final id in ids) id: seed(id)},
      needsEnabled: true,
      timeOfDay: 'evening',
      dayCount: 3,
      storyStartDate: _storyDate,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-parity',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (var i = 0; i < ids.length; i++) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: ids[i],
          groupId: 'grp-parity',
          name: names[i],
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-parity',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    await chat.setNeedsSimEnabled(true);
    return _GroupChat(db, chat);
  }
}

/// Boot a group, run [prepare] on it (a switch flip), and let the writes land
/// before the first frame, so no golden captures a half-written state.
Future<_GroupChat> _group3(
  WidgetTester tester,
  StorageService storage, {
  Future<void> Function(_GroupChat g)? prepare,
}) async {
  final g = (await tester.runAsync(
    () => _GroupChat.boot(storage, ['Ana', 'Bea', 'Cy']),
  ))!;
  addTearDown(
    () => tester.runAsync(() => disposeChatThenCloseDb(g.chat, g.db)),
  );
  if (prepare != null) await tester.runAsync(() => prepare(g));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  return g;
}

void main() {
  setupPathProviderMock();

  testWidgets(
    'Character State — 1:1 baseline, Realism, Needs and Afterglow on',
    (tester) async {
      final storage = await _storage(tester);
      final g = (await tester.runAsync(() => _bootOneToOne(storage)))!;
      addTearDown(
        () => tester.runAsync(() => disposeChatThenCloseDb(g.chat, g.db)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await expectThemedGoldens(
        tester,
        child: _host(
          storage,
          g.chat,
          CharacterStateGroup(
            chat: g.chat,
            isGroup: false,
            initiallyExpanded: true,
          ),
        ),
        group: _group,
        name: 'character_state_1to1',
        surface: _surface,
        settle: false,
      );
    },
  );

  testWidgets(
    'Character State — group member, all switches on (looks like 1:1)',
    (tester) async {
      final storage = await _storage(tester);
      final g = await _group3(tester, storage);
      await expectThemedGoldens(
        tester,
        child: _host(
          storage,
          g.chat,
          CharacterStateGroup(
            chat: g.chat,
            isGroup: true,
            member: g.member('Ana'),
            initiallyExpanded: true,
          ),
        ),
        group: _group,
        name: 'character_state_group',
        surface: _surface,
        settle: false,
      );
    },
  );

  testWidgets('Character State — group member, Realism off for Ana only', (
    tester,
  ) async {
    final storage = await _storage(tester);
    final g = await _group3(
      tester,
      storage,
      prepare: (g) => g.chat.setMemberRealismEnabled(g.idOf('Ana'), false),
    );
    expect(g.chat.realismSwitchFor(g.idOf('Ana')), isFalse);
    expect(g.chat.realismSwitchFor(g.idOf('Bea')), isTrue, reason: 'only Ana');
    await expectThemedGoldens(
      tester,
      child: _host(
        storage,
        g.chat,
        CharacterStateGroup(
          chat: g.chat,
          isGroup: true,
          member: g.member('Ana'),
          initiallyExpanded: true,
        ),
      ),
      group: _group,
      name: 'character_state_group_realism_off',
      surface: _surface,
      settle: false,
    );
  });

  testWidgets('Character State — group member, Needs off for Ana only', (
    tester,
  ) async {
    final storage = await _storage(tester);
    final g = await _group3(
      tester,
      storage,
      prepare: (g) => g.chat.setMemberNeedsEnabled(g.idOf('Ana'), false),
    );
    expect(g.chat.needsSwitchFor(g.idOf('Ana')), isFalse);
    expect(g.chat.needsSwitchFor(g.idOf('Bea')), isTrue, reason: 'only Ana');
    await expectThemedGoldens(
      tester,
      child: _host(
        storage,
        g.chat,
        CharacterStateGroup(
          chat: g.chat,
          isGroup: true,
          member: g.member('Ana'),
          initiallyExpanded: true,
        ),
      ),
      group: _group,
      name: 'character_state_group_needs_off',
      surface: _surface,
      settle: false,
    );
  });

  testWidgets('Group Dynamics — Ana toward two others', (tester) async {
    final storage = await _storage(tester);
    final g = await _group3(tester, storage);
    expect(GroupDynamicsSection.visibleFor(g.chat, g.member('Ana')), isTrue);
    await expectThemedGoldens(
      tester,
      child: _host(
        storage,
        g.chat,
        GroupDynamicsSection(
          chat: g.chat,
          member: g.member('Ana'),
          initiallyExpanded: true,
        ),
      ),
      group: _group,
      name: 'group_dynamics',
      surface: const Size(380, 360),
      settle: false,
    );
  });
}
