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

// GROUP TURNS MUST READ THE PINNED SPEAKER'S JOB, NOT `_activeCharacter`.
//
// setActiveGroup nulls `_activeCharacter`. Prompt compose still built
// occupation / hours / occupationBrief from that field, so group chats
// got an empty job, empty hours (fail-closed to not-at-work), and no
// brief — while the skip banner already used `_workFieldsFor` on the
// real speaker card. The leaf test "group at-work prompt injects the
// same brief" stubbed getOccupationBrief on a bare BehavioralInjection
// and never went through this wiring.
//
// Proven red: debugBuildPositionInjection() after setActiveGroup + pin
// returned '' (no "At work as a …", no brief).

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
          return Directory.systemTemp.createTempSync('fpai_grpwork_').path;
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
  late GroupRealismBlobs blobs;

  const brief = 'Keeps the diner grill and the late-night register';

  setUp(() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
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

    blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: false,
      timeOfDay: 'afternoon',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-work',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-ana',
        groupId: 'grp-work',
        name: 'Ana',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-ana.png'),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: 'grp-work',
        name: 'Bea',
        firstMessage: const Value('The grill is already hot.'),
        avatarFilename: const Value('mem-bea.png'),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: true,
              occupation: 'clerk',
              hours: '9-5',
              occupationBrief: brief,
            ).toJson(),
          ),
        ),
      ),
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('group at-work prompt injects the pinned speaker brief', () async {
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-work',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );

    expect(
      chat.activeCharacter,
      isNull,
      reason: 'setActiveGroup nulls the 1:1 host; that is the bug surface',
    );
    expect(chat.realismEnabled, isTrue);
    expect(chat.groupCharacters, hasLength(2));

    final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
    chat.debugPinTurnSpeakerForRealism(bea.stableGroupId);
    await chat.timeService.setClockDirect(DateTime.utc(2026, 1, 1, 14, 30));

    final txt = chat.debugBuildPositionInjection();
    expect(
      txt,
      contains('At work as a clerk'),
      reason:
          'THE BUG: occupation/hours/brief still read `_activeCharacter`, '
          'which is null in group, so the live injection is empty even '
          'though the skip banner already uses the speaker card.',
    );
    expect(txt, contains(brief));
    expect(txt, contains('Write from there.'));
  });
}
