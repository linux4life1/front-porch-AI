// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Needs Reset must target the per-member store id
// (groupMemberStoreId), not stableGroupId. Members with no avatar file
// have store id == dbId and stableGroupId == name — those two disagree.
// Resetting Bea must clear Bea's live Needs and leave Ava's alone.

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
          return Directory.systemTemp
              .createTempSync('fpai_grp_needs_reset_')
              .path;
        }
        return null;
      });
}

Map<String, dynamic> _dirtySeed(int hunger) {
  final seed = defaultGroupMemberRealismSeed();
  seed['needs'] = <String, int>{
    'hunger': hunger,
    'bladder': hunger,
    'energy': hunger,
    'social': hunger,
    'fun': hunger,
    'hygiene': hunger,
    'comfort': hunger,
  };
  return seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'resetRealismForGroupCharacter clears only the store-id member',
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

      const groupId = 'grp-needs-reset';
      final blobs = buildGroupRealismBlobs(
        seeds: {'mem-ava': _dirtySeed(30), 'mem-bea': _dirtySeed(20)},
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: groupId,
          name: 'The Stoop',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in [
        (id: 'mem-ava', name: 'Ava'),
        (id: 'mem-bea', name: 'Bea'),
      ]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.id,
            groupId: groupId,
            name: m.name,
            firstMessage: const Value('Evening.'),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(
          id: groupId,
          name: 'The Stoop',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final ava = chat.groupCharacters.firstWhere((c) => c.name == 'Ava');
      final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
      expect(ava.imagePath, anyOf(isNull, isEmpty));
      expect(bea.imagePath, anyOf(isNull, isEmpty));
      expect(groupMemberStoreId(bea), bea.dbId);
      expect(groupMemberStoreId(bea), isNot(bea.stableGroupId));

      expect(chat.getNeedsForGroupCharacter(ava)['hunger'], 30);
      expect(chat.getNeedsForGroupCharacter(bea)['hunger'], 20);

      chat.resetRealismForGroupCharacter(bea);

      expect(
        chat.getNeedsForGroupCharacter(bea),
        isEmpty,
        reason: 'Bea\'s store-id slot must be dropped — not keyed by name',
      );
      expect(
        chat.getNeedsForGroupCharacter(ava)['hunger'],
        30,
        reason: 'Ava\'s Needs must survive a Reset aimed at Bea',
      );
    },
  );
}
