// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A group member row with avatarFilename == null still seeds Needs.
// group_smoke writes avatarFilename on the DB row and must not invent
// PNG files; this pin covers the null-filename sibling.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_null_av_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'group member with null avatarFilename still gets Needs seeded',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
        'passage_of_time_default': true,
      });
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final storage = StorageService();
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage));
      addTearDown(chat.dispose);
      await storage.initialized;

      final blobs = buildGroupRealismBlobs(
        seeds: {'mem-ana': defaultGroupMemberRealismSeed()},
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-null-av',
          name: 'No PNG',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana',
          groupId: 'grp-null-av',
          name: 'Ana',
          firstMessage: const Value('Evening.'),
        ),
      );
      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-null-av',
          name: 'No PNG',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(ana.imagePath, anyOf(isNull, isEmpty));
      final needs = chat.getNeedsForGroupCharacter(ana);
      expect(
        needs,
        isNotEmpty,
        reason: 'null avatarFilename must still seed a Needs vector',
      );
      expect(needs['hunger'], isNotNull);
    },
  );
}
