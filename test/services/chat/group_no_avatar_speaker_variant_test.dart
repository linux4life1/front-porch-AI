// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A roster member with avatarFilename == null still has dbId ==
// GroupMember.id; stableGroupId falls back to the display name. At
// 7a74f880, group_speaker_resolution.dart:51 and
// chat_service_variants.dart:37 compared only c.stableGroupId, so a
// UUID-stamped greeting missed the member. UUID-first keys must still
// resolve that speaker and hand them variants / Needs / posture under
// groupMemberStoreId(c). Sender is never a unique name match, so a
// name-only compare cannot hide the miss.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/group_speaker_resolution.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_no_av_spk_').path;
        }
        return null;
      });
}

CharacterCard _noAvatar(String name, String dbId) =>
    CharacterCard(name: name, firstMessage: 'Hi $dbId.')..dbId = dbId;

ChatMessage _stamp(String sender, String characterId) => ChatMessage(
  text: 'something they said',
  isUser: false,
  sender: sender,
  characterId: characterId,
);

Map<String, dynamic> _seed({required int hunger, required String stance}) {
  final seed = defaultGroupMemberRealismSeed();
  seed['spatialStance'] = stance;
  seed['needs'] = <String, int>{
    'hunger': hunger,
    'bladder': 80,
    'energy': 80,
    'social': 80,
    'fun': 80,
    'hygiene': 80,
    'comfort': 80,
  };
  return seed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('no-avatar duplicate names resolve the UUID-stamped speaker', () {
    final anaA = _noAvatar('Ana', 'mem-ana-a');
    final anaB = _noAvatar('Ana', 'mem-ana-b');
    expect(anaA.imagePath, anyOf(isNull, isEmpty));
    expect(anaB.imagePath, anyOf(isNull, isEmpty));
    expect(groupMemberStoreId(anaA), 'mem-ana-a');
    expect(groupMemberStoreId(anaB), 'mem-ana-b');
    expect(anaA.stableGroupId, 'Ana');
    expect(anaB.stableGroupId, 'Ana');
    expect(groupMemberStoreId(anaB), isNot(anaB.stableGroupId));

    final cast = [anaA, anaB];
    // Sender matches both members; name fallback must refuse. The stamp
    // is the UUID — a stableGroupId-only compare (7a74f880) misses both.
    final fromB = _stamp('Ana', groupMemberStoreId(anaB));
    expect(
      resolveGroupSpeakerForMessage(cast, fromB)?.dbId,
      'mem-ana-b',
      reason:
          'group_speaker_resolution.dart:51 must match groupMemberStoreId, '
          'not only the name-keyed stableGroupId',
    );
    expect(
      resolveGroupSpeakerForMessage(
        cast,
        _stamp('NotAMember', 'mem-ana-a'),
      )?.dbId,
      'mem-ana-a',
      reason: 'a sender that matches nobody must still resolve by UUID',
    );
  });

  test(
    'no-avatar member greeting variants, Needs and posture key by UUID',
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
        seeds: {
          'mem-ana-a': _seed(hunger: 11, stance: 'on the porch rail'),
          'mem-ana-b': _seed(hunger: 22, stance: 'leaning on the doorframe'),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-no-av',
          name: 'No PNG',
          firstMessage: const Value(''),
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana-a',
          groupId: 'grp-no-av',
          name: 'Ana',
          firstMessage: const Value('From A.'),
          alternateGreetings: const Value('["Alt A."]'),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana-b',
          groupId: 'grp-no-av',
          name: 'Ana',
          firstMessage: const Value('From B.'),
          alternateGreetings: const Value('["Alt B."]'),
        ),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-no-av',
          characterId: const Value('group_grp-no-av'),
          groupId: const Value('grp-no-av'),
          realismEnabled: const Value(true),
          needsSimEnabled: const Value(true),
          groupRealismState: Value(blobs.defaultMemberJson),
        ),
      );
      // Greeting stamped with B's UUID. Sender is not a roster name, so
      // chat_service_variants.dart:37 cannot be saved by a name compare.
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'm0',
          sessionId: 'sess-no-av',
          position: 0,
          sender: 'NotAMember',
          isUser: false,
          characterId: const Value('mem-ana-b'),
          swipes: Value(jsonEncode(['From B.'])),
        ),
      );

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-no-av',
          name: 'No PNG',
          firstMessage: '',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      if (chat.currentSessionId != 'sess-no-av') {
        await chat.loadSession('sess-no-av');
      }

      final anaA = chat.groupCharacters.firstWhere(
        (c) => c.dbId == 'mem-ana-a',
      );
      final anaB = chat.groupCharacters.firstWhere(
        (c) => c.dbId == 'mem-ana-b',
      );
      expect(anaA.imagePath, anyOf(isNull, isEmpty));
      expect(anaB.imagePath, anyOf(isNull, isEmpty));
      expect(groupMemberStoreId(anaA), 'mem-ana-a');
      expect(groupMemberStoreId(anaB), 'mem-ana-b');
      expect(anaA.stableGroupId, 'Ana');
      expect(anaB.stableGroupId, 'Ana');

      expect(chat.messages, isNotEmpty);
      expect(chat.messages.first.characterId, groupMemberStoreId(anaB));
      expect(
        resolveGroupSpeakerForMessage(
          chat.groupCharacters,
          chat.messages.first,
        )?.dbId,
        'mem-ana-b',
        reason:
            'UUID-stamped greeting of a no-avatar member must resolve the '
            'speaker even when the sender is not a unique name',
      );

      expect(
        chat.openingAllGreetings,
        ['From B.', 'Alt B.'],
        reason:
            'chat_service_variants.dart:37 must match groupMemberStoreId, '
            'not only the name-keyed stableGroupId',
      );
      expect(chat.variantsForMessage(0).map((v) => v.text), [
        'From B.',
        'Alt B.',
      ], reason: 'the greeting picker must cycle B\'s card greets, not A\'s');

      expect(chat.getNeedsForGroupCharacter(anaB)['hunger'], 22);
      expect(chat.getNeedsForGroupCharacter(anaA)['hunger'], 11);
      expect(
        chat.spatialStanceForGroupCharacter(anaB),
        'leaning on the doorframe',
      );
      expect(chat.spatialStanceForGroupCharacter(anaA), 'on the porch rail');

      await chat.flushPendingSaves();
      final row = await db.getSessionById(chat.currentSessionId!);
      final perChar =
          (jsonDecode(row!.groupRealismState) as Map)['perChar'] as Map;
      expect(perChar.containsKey('mem-ana-b'), isTrue);
      expect(perChar.containsKey('Ana'), isFalse);
      expect(((perChar['mem-ana-b'] as Map)['needs'] as Map)['hunger'], 22);
      expect(
        (perChar['mem-ana-b'] as Map)['spatialStance'],
        'leaning on the doorframe',
      );
    },
  );
}
