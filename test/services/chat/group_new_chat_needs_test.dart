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

// "NEW CHAT" INSIDE A GROUP MUST NOT TURN NEEDS OFF.
//
// startNewChat's non-1:1 branch zeroes the per-chat realism config, then
// rebuilds `_groupRealism` from the group's member seeds — but it never
// re-derived `_needsSimEnabled` from those seeds the way fresh group ENTRY
// does (chat_service_group_entry.dart) and the way the 1:1 branch re-seeds
// from the card. So the flag stayed false, `_saveChat` wrote false onto the
// new session row, and `_hydrateSessionScalars` read it straight back on
// every reload: blank needs grids and no decay for the rest of that
// conversation, in a group whose first chat had needs working.
//
// Red-proved: deleting the re-derivation makes the second expectation fail
// with "needs stayed off after New Chat".

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;

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
          return Directory.systemTemp.createTempSync('fpai_grp_needs_').path;
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
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
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<GroupChat> seedGroup({required bool needsEnabled}) async {
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: needsEnabled,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-needs',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-needs',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    return GroupChat(
      id: 'grp-needs',
      name: 'The Porch',
      defaultMemberRealismState: blobs.defaultMemberJson,
      baselineRealismState: blobs.baselineJson,
    );
  }

  test('New Chat inside a needs-enabled group keeps Needs on', () async {
    final group = await seedGroup(needsEnabled: true);
    await chat.setActiveGroup(
      group,
      groupRepo: GroupChatRepository(storage, db),
    );
    expect(
      chat.needsSimEnabled,
      isTrue,
      reason: 'fresh group entry infers Needs from the member seeds',
    );

    await chat.startNewChat();

    expect(
      chat.needsSimEnabled,
      isTrue,
      reason:
          'needs stayed off after New Chat — the flag is then persisted '
          'onto the new session row and read back on every reload',
    );
    // The flag really is what gets written for the new session.
    final row = await db.getSessionById(chat.currentSessionId!);
    expect(row?.needsSimEnabled, isTrue);
  });

  test(
    'a group authored WITHOUT needs still starts a new chat with them off',
    () async {
      final group = await seedGroup(needsEnabled: false);
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );
      expect(chat.needsSimEnabled, isFalse);

      await chat.startNewChat();

      expect(
        chat.needsSimEnabled,
        isFalse,
        reason: 'presence-inference must not invent needs the creator omitted',
      );
    },
  );
}
