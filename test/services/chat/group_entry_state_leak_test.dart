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

// WALKING INTO A GROUP MUST NOT CARRY THE LAST CHAT IN WITH YOU.
//
// setActiveGroup zeroed a long list of per-chat state but skipped three
// things, and each one was then written onto the group's FIRST session row by
// the `_saveChat()` at the end of that method — i.e. permanent for the life of
// that conversation:
//
//  1. Chaos: only the two switches were seeded ("pressure left as-is or
//     explicitly zeroed by caller"), so the previous chat's chance-time
//     pressure — and an un-delivered manual SPIN NOW event, which injects as
//     CANON with no chaos-enabled gate — walked in. The 1:1 twin calls
//     resetForFreshChat() before its seed; this one called nothing.
//  2. Realism/Needs: the promotion block only runs when the group definition
//     carries member realism seeds, so a group authored WITHOUT them simply
//     inherited the previous chat's flags and needs vector.
//  3. The global Porch Life "Needs" switch AND-gates all four 1:1/import seed
//     sites and was missing here, making it quietly 1:1-only — exactly the
//     failure the Chaos global's own comment two lines above warns about.
//
// Red-proved: each test fails on the pre-fix code (chaos pressure survives,
// realism/needs read back as the 1:1's, needs stays on with the global off).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_leak_').path;
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

  Future<void> boot({bool needsGlobal = true}) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'needs_sim_default': needsGlobal,
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
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  /// A 1:1 host with the engine, Needs and Chaos all live — the chat the user
  /// is leaving.
  CharacterCard hostCard(String dbId) => CharacterCard(
    name: 'Mara',
    description: 'Exists only inside the group-entry leak test.',
    firstMessage: 'The porch light hums.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: true,
      needsSimEnabled: true,
      chaosModeEnabled: true,
    ),
  )..dbId = dbId;

  /// [seeds] false = a group authored with no member realism state at all,
  /// which is what `forkToGroupChat` and any realism-less wizard run produce.
  Future<GroupChat> seedGroup(
    String id, {
    required bool seeds,
    bool needsEnabled = true,
  }) async {
    final blobs = seeds
        ? buildGroupRealismBlobs(
            seeds: {'$id-ana': defaultGroupMemberRealismSeed()},
            needsEnabled: needsEnabled,
            timeOfDay: 'morning',
            dayCount: 1,
          )
        : null;
    await db.insertGroup(
      GroupsCompanion.insert(
        id: id,
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs?.defaultMemberJson ?? '{}'),
        baselineRealismState: Value(blobs?.baselineJson ?? '{}'),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: '$id-ana',
        groupId: id,
        name: 'Ana',
        firstMessage: const Value('Evening.'),
      ),
    );
    return GroupChat(
      id: id,
      name: 'The Porch',
      defaultMemberRealismState: blobs?.defaultMemberJson ?? '{}',
      baselineRealismState: blobs?.baselineJson ?? '{}',
    );
  }

  test(
    'chance-time pressure from the last chat does not follow you in',
    () async {
      await boot();
      await chat.setActiveCharacter(hostCard('char-leak-1'));
      expect(chat.chaosModeService.chaosModeEnabled, isTrue);

      // A few turns of ambient pressure in the 1:1.
      for (var i = 0; i < 3; i++) {
        chat.checkAndTickChaosPressure();
      }
      expect(chat.chaosPressure, greaterThan(0));

      final group = await seedGroup('grp-leak-1', seeds: true);
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(
        chat.chaosPressure,
        0,
        reason:
            'the group never rolled a die — inherited pressure makes its very '
            'first turns as likely to fire as the end of a long 1:1, and the '
            'entry save bakes it onto the session row',
      );
      expect(
        chat.chaosModeService.chaosModeEnabled,
        isFalse,
        reason: 'this group asked for Chaos off and the global default is off',
      );
      final row = await db.getSessionById(chat.currentSessionId!);
      expect(row?.chaosPressure, 0);
    },
  );

  test(
    'a group with no realism seeds does not inherit the 1:1 engine/needs',
    () async {
      await boot();
      await chat.setActiveCharacter(hostCard('char-leak-2'));
      expect(chat.realismEnabled, isTrue);
      expect(chat.needsSimEnabled, isTrue);

      final group = await seedGroup('grp-leak-2', seeds: false);
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(
        chat.realismEnabled,
        isFalse,
        reason:
            'nothing in this group asked for the engine — it ran (and paid for '
            'per-turn evals) only because the previous chat had it on',
      );
      expect(chat.needsSimEnabled, isFalse);
      final row = await db.getSessionById(chat.currentSessionId!);
      expect(row?.realismEnabled, isFalse);
      expect(row?.needsSimEnabled, isFalse);
    },
  );

  test(
    'the global Needs switch vetoes a group the same way it vetoes a 1:1',
    () async {
      await boot(needsGlobal: false);
      final group = await seedGroup('grp-leak-3', seeds: true);
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );

      expect(
        chat.realismEnabled,
        isTrue,
        reason: 'the Needs veto must not take the whole engine with it',
      );
      expect(
        chat.needsSimEnabled,
        isFalse,
        reason:
            'Porch Life → Needs off must mean off in groups too; before the fix '
            'the switch was silently 1:1-only',
      );
      final row = await db.getSessionById(chat.currentSessionId!);
      expect(row?.needsSimEnabled, isFalse);
    },
  );

  test('with the global ON the member seeds still turn Needs on', () async {
    await boot();
    final group = await seedGroup('grp-leak-4', seeds: true);
    await chat.setActiveGroup(
      group,
      groupRepo: GroupChatRepository(storage, db),
    );

    expect(
      chat.needsSimEnabled,
      isTrue,
      reason: 'the AND-gate must not become a veto of its own',
    );
  });
}
