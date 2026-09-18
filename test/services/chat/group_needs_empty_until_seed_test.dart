// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A group member with no stored needs map must not be invented as the
// 75/65 needDefaults table. Live-add and first decay seed from the card.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_gneeds_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('storedNeedsOrEmpty: no map → empty; partial fills missing keys', () {
    expect(NeedsSimulation.storedNeedsOrEmpty(null), isEmpty);
    expect(NeedsSimulation.storedNeedsOrEmpty({}), isEmpty);
    final partial = NeedsSimulation.storedNeedsOrEmpty({'hunger': 12});
    expect(partial['hunger'], 12);
    expect(partial['bladder'], NeedsSimulation.needDefaults['bladder']);
    expect(partial.length, NeedsSimulation.needKeys.length);
  });

  test('baselinesFromExtensions uses the card, not the 75/65 table', () {
    final ext = FrontPorchExtensions(
      needsBaselineHunger: 40,
      needsBaselineBladder: 41,
      needsBaselineEnergy: 42,
      needsBaselineSocial: 43,
      needsBaselineFun: 44,
      needsBaselineHygiene: 45,
      needsBaselineComfort: 46,
    );
    final seeded = NeedsSimulation.baselinesFromExtensions(ext);
    expect(seeded['hunger'], 40);
    expect(seeded['comfort'], 46);
    expect(
      seeded['hunger'],
      isNot(NeedsSimulation.needDefaults['hunger']),
      reason: 'card hunger 40 must not be rewritten as needDefaults 75',
    );
    expect(
      NeedsSimulation.baselinesFromExtensions(null),
      NeedsSimulation.needDefaults,
    );
  });

  group('ChatService group slot', () {
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

    tearDown(() async {
      chat.dispose();
      await db.close();
    });

    Future<void> seedGroup({required bool needsEnabled}) async {
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
          id: 'grp-empty-needs',
          name: 'The Porch',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.$1,
            groupId: 'grp-empty-needs',
            name: m.$2,
            firstMessage: const Value('Evening.'),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-empty-needs',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
    }

    test('member with no stored map → empty, not the 75/65 table', () async {
      await seedGroup(needsEnabled: false);
      expect(chat.debugGroupNeeds('mem-ana'), isEmpty);
    });

    test('seeded member has a stored map from the group seed', () async {
      await seedGroup(needsEnabled: true);
      final seeded = chat.debugGroupNeeds('mem-ana');
      expect(seeded, isNotEmpty);
      final wizard =
          defaultGroupMemberRealismSeed()['needs'] as Map<String, int>;
      expect(seeded['hunger'], wizard['hunger']);
      expect(seeded['social'], wizard['social']);
    });
  });
}
