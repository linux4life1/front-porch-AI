// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group objectives keyed by the legacy name/stableGroupId survive
// migrateGroupStoreKeys onto the UUID, and group_card_exporter.dart:83
// exports them under that UUID.

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

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_obj_mig_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'legacy-keyed group objectives are readable under UUID and export',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'objectives_enabled': true,
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

      const objectiveText = 'Keep the porch swept.';
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-obj', name: 'Objectives'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana',
          groupId: 'grp-obj',
          name: 'Ana',
          firstMessage: const Value('Evening.'),
        ),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-obj',
          characterId: const Value('group_grp-obj'),
          groupId: const Value('grp-obj'),
          groupRealismState: Value(
            jsonEncode({
              'perChar': {'Ana': defaultGroupMemberRealismSeed()},
              'objectives': {
                'Ana': [
                  {'objective': objectiveText, 'active': true},
                ],
              },
            }),
          ),
        ),
      );
      await db.insertObjective(
        ObjectivesCompanion.insert(
          id: 'obj-ana-sweep',
          characterId: 'Ana',
          objective: objectiveText,
          tasks: const Value('[{"description":"sweep","completed":false}]'),
        ),
      );

      await chat.setActiveGroup(
        GroupChat(id: 'grp-obj', name: 'Objectives'),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(groupMemberStoreId(ana), 'mem-ana');
      expect(ana.stableGroupId, 'Ana');

      final live = chat.getObjectivesForGroupCharacter(ana);
      expect(
        live.map((o) => o.objective),
        contains(objectiveText),
        reason: 'name-keyed objectives must be readable under the UUID key',
      );

      final underUuid = await db.getObjectivesForCharacter('mem-ana');
      expect(
        underUuid.map((o) => o.objective),
        contains(objectiveText),
        reason: 'migrateGroupStoreKeys must move the DB row onto the UUID',
      );
      expect(await db.getObjectivesForCharacter('Ana'), isEmpty);

      final group = GroupChat(id: 'grp-obj', name: 'Objectives');
      final exported = await GroupCardExporter(
        GroupChatRepository(storage, db),
        storage,
        db,
      ).buildGroupCard(group);
      expect(exported, isNotNull);
      final bundled = exported!.memberObjectives['mem-ana'];
      expect(
        bundled,
        isNotNull,
        reason: 'exporter :83 looks up groupMemberStoreId, not the name key',
      );
      expect(bundled!.map((o) => o['objective']), contains(objectiveText));
    },
  );
}
