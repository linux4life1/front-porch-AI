// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A lived-in group blob keyed by the member's display name must load
// onto the member UUID and be saved once under that UUID — never both.

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
          return Directory.systemTemp.createTempSync('fpai_store_mig_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'legacy name-keyed group blob migrates to UUID once, not duplicated',
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

      final seed = defaultGroupMemberRealismSeed();
      seed['affection'] = 77;
      seed['needs'] = <String, int>{
        'hunger': 11,
        'bladder': 80,
        'energy': 80,
        'social': 80,
        'fun': 80,
        'hygiene': 80,
        'comfort': 80,
      };
      final tipBlob = jsonEncode({
        'perChar': {'Ana': seed},
      });

      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-mig', name: 'Migrate'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana',
          groupId: 'grp-mig',
          name: 'Ana',
          firstMessage: const Value('Evening.'),
        ),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-mig',
          characterId: const Value('group_grp-mig'),
          groupId: const Value('grp-mig'),
          realismEnabled: const Value(true),
          needsSimEnabled: const Value(true),
          groupRealismState: Value(tipBlob),
        ),
      );

      await chat.setActiveGroup(
        GroupChat(id: 'grp-mig', name: 'Migrate'),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(groupMemberStoreId(ana), 'mem-ana');
      expect(groupMemberStoreId(ana), isNot(ana.stableGroupId));
      expect(
        chat.getAffectionForGroupCharacter(ana),
        77,
        reason: 'legacy Ana key must land on mem-ana with values intact',
      );
      expect(chat.getNeedsForGroupCharacter(ana)['hunger'], 11);

      await chat.flushPendingSaves();
      final row = await db.getSessionById(chat.currentSessionId!);
      expect(row, isNotNull);
      final perChar =
          (jsonDecode(row!.groupRealismState) as Map)['perChar'] as Map;
      expect(
        perChar.containsKey('mem-ana'),
        isTrue,
        reason: 'migrated blob is saved under the UUID',
      );
      expect(
        perChar.containsKey('Ana'),
        isFalse,
        reason: 'legacy name key must not be kept beside the UUID',
      );
      expect((perChar['mem-ana'] as Map)['affection'], 77);
    },
  );

  test('legacy member with no UUID still keys by stableGroupId', () {
    final card = CharacterCard(name: 'Legacy Lea');
    expect(card.dbId, isNull);
    expect(groupMemberStoreId(card), card.stableGroupId);
    expect(groupMemberStoreId(card), 'Legacy_Lea');
    final store = <String, int>{card.stableGroupId: 44};
    expect(
      migrateGroupStoreKeys(store, [card]),
      isFalse,
      reason: 'no UUID → dest == legacy, nothing to move',
    );
    expect(store.keys, ['Legacy_Lea']);
    expect(store['Legacy_Lea'], 44);
  });

  test(
    'name-keyed Needs and posture migrate once; second open does not duplicate',
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
      Future<ChatService> open() async {
        final next =
            ChatService(
                KoboldService(storage),
                UserPersonaService(db),
                storage,
                WorldRepository(storage, db),
              )
              ..setDatabase(db)
              ..setCharacterRepository(CharacterRepository(db, storage));
        await storage.initialized;
        await next.setActiveGroup(
          GroupChat(id: 'grp-mig2', name: 'Migrate2'),
          groupRepo: GroupChatRepository(storage, db),
        );
        for (var i = 0; i < 40 && next.groupCharacters.isEmpty; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        return next;
      }

      final seed = defaultGroupMemberRealismSeed();
      seed['affection'] = 77;
      seed['spatialStance'] = 'on the porch rail';
      seed['needs'] = <String, int>{
        'hunger': 11,
        'bladder': 80,
        'energy': 80,
        'social': 80,
        'fun': 80,
        'hygiene': 80,
        'comfort': 80,
      };
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-mig2', name: 'Migrate2'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana',
          groupId: 'grp-mig2',
          name: 'Ana',
          firstMessage: const Value('Evening.'),
        ),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-mig2',
          characterId: const Value('group_grp-mig2'),
          groupId: const Value('grp-mig2'),
          realismEnabled: const Value(true),
          needsSimEnabled: const Value(true),
          groupRealismState: Value(
            jsonEncode({
              'perChar': {'Ana': seed},
            }),
          ),
        ),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'm0',
          sessionId: 'sess-mig2',
          position: 0,
          sender: 'Ana',
          isUser: false,
          swipes: Value(jsonEncode(['Evening.'])),
        ),
      );

      var chat = await open();
      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(groupMemberStoreId(ana), 'mem-ana');
      expect(chat.getAffectionForGroupCharacter(ana), 77);
      expect(chat.getNeedsForGroupCharacter(ana)['hunger'], 11);
      expect(chat.spatialStanceForGroupCharacter(ana), 'on the porch rail');

      await chat.flushPendingSaves();
      Future<Map<String, dynamic>> persistedPerChar() async {
        final row = await db.getSessionById(chat.currentSessionId!);
        return (jsonDecode(row!.groupRealismState) as Map)['perChar']
            as Map<String, dynamic>;
      }

      var perChar = await persistedPerChar();
      expect(perChar.containsKey('mem-ana'), isTrue);
      expect(perChar.containsKey('Ana'), isFalse);
      expect((perChar['mem-ana'] as Map)['affection'], 77);
      expect((perChar['mem-ana'] as Map)['spatialStance'], 'on the porch rail');
      expect(((perChar['mem-ana'] as Map)['needs'] as Map)['hunger'], 11);

      chat.dispose();
      chat = await open();
      addTearDown(chat.dispose);
      final ana2 = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(groupMemberStoreId(ana2), 'mem-ana');
      expect(chat.getAffectionForGroupCharacter(ana2), 77);
      expect(chat.getNeedsForGroupCharacter(ana2)['hunger'], 11);
      expect(chat.spatialStanceForGroupCharacter(ana2), 'on the porch rail');
      await chat.flushPendingSaves();
      perChar = await persistedPerChar();
      expect(
        perChar.keys.toList(),
        ['mem-ana'],
        reason:
            'second open must not re-migrate or keep a name key beside UUID',
      );
      expect((perChar['mem-ana'] as Map)['affection'], 77);
    },
  );
}
