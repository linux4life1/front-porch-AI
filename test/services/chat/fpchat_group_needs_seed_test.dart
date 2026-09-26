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

// IMPORTING A CHAT INTO A GROUP MUST NOT SWITCH NEEDS OFF.
//
// `_seedLiveRealismForImportedSession` reseeds live state from the card so the
// save cannot bleed the previously open chat. Its 1:1 branch re-derives Needs
// from the card; its else branch just wrote `_needsSimEnabled = false` and
// stopped — which was correct for "no chat open" and dead wrong for a GROUP.
//
// The result a user saw: import a transcript into a group whose members were
// authored WITH needs, and the whole rest of that conversation has blank needs
// grids and no decay — because the import's `_saveChat()` baked `false` onto
// the brand-new session row.
//
// The fix re-derives from the member seeds exactly as fresh group entry does
// (presence-inference: the wizard omits the per-member 'needs' sub-map when
// Needs was off), AND-gated by the Porch Life global like every other seed
// site.
//
// Red-proved: with the re-derive removed, the first test reads back false.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_gimport_').path;
        }
        return null;
      });
}

/// A plain SillyTavern-style transcript: no `fpai` block, so the importer
/// takes the dialogue-only path and the seed above is the last word on Needs.
Uint8List transcriptBytes() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'messages': [
        {'name': 'User', 'is_user': true, 'mes': 'evening all'},
        {'name': 'Ana', 'is_user': false, 'mes': 'evening'},
      ],
    }),
  ),
);

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

  /// [needsEnabled] false = a group authored with Needs off in the wizard, so
  /// the per-member seeds carry no 'needs' sub-map at all.
  Future<GroupChat> enterGroup(String id, {bool needsEnabled = true}) async {
    final blobs = buildGroupRealismBlobs(
      seeds: {'$id-ana': defaultGroupMemberRealismSeed()},
      needsEnabled: needsEnabled,
      timeOfDay: 'evening',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: id,
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
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
    final group = GroupChat(
      id: id,
      name: 'The Porch',
      defaultMemberRealismState: blobs.defaultMemberJson,
      baselineRealismState: blobs.baselineJson,
    );
    await chat.setActiveGroup(
      group,
      groupRepo: GroupChatRepository(storage, db),
    );
    return group;
  }

  test(
    'a transcript imported into a group keeps its Needs simulation',
    () async {
      await boot();
      await enterGroup('grp-imp-1');
      expect(
        chat.needsSimEnabled,
        isTrue,
        reason: 'sanity: entry seeded it on',
      );

      await chat.importChatPackage(transcriptBytes());

      expect(
        chat.needsSimEnabled,
        isTrue,
        reason:
            'the members are authored with needs — importing a transcript '
            'must not switch the simulation off for the rest of the chat',
      );
      final row = await db.getSessionById(chat.currentSessionId!);
      expect(
        row?.needsSimEnabled,
        isTrue,
        reason:
            'and the import save must not bake false onto the new session '
            'row, which is what made it permanent',
      );
    },
  );

  test('a group authored without needs still imports with them off', () async {
    await boot();
    await enterGroup('grp-imp-2', needsEnabled: false);

    await chat.importChatPackage(transcriptBytes());

    expect(
      chat.needsSimEnabled,
      isFalse,
      reason:
          'presence-inference must not invent needs the wizard never '
          'wrote — the re-derive is not a blanket "on"',
    );
  });

  test('the Porch Life global vetoes it on import too', () async {
    await boot(needsGlobal: false);
    await enterGroup('grp-imp-3');

    await chat.importChatPackage(transcriptBytes());

    expect(
      chat.needsSimEnabled,
      isFalse,
      reason:
          'every other seed site AND-gates on the global; the import '
          'path must not be the one door that ignores it',
    );
  });
}
