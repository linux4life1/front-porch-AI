// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Soft-on-roster Scene Guests in a group: reload keeps tier, feelings
// exclude soft, promote one leaves the others lite, and 1:1→group carries
// present guests as soft members. Proven red: restore the toCharacterCard
// strip, or convert 1:1 guests as full, and these fail.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_group_lite_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';
const _lite = '{"version":"2.5","realism_engine":{"tier":"lite"}}';

CharacterCard _lib(String name) => CharacterCard(
  name: name,
  description: 'Library card for the group-lite test.',
  firstMessage: 'Hello from $name.',
  personality: '$name personality',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: false,
    needsSimEnabled: false,
    chaosModeEnabled: false,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['They step onto the porch.'],
    );
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..setGroupChatRepository(GroupChatRepository(storage, db))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  Future<void> insertMember({
    required String id,
    required String name,
    String ext = _off,
  }) async {
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: id,
        groupId: 'grp-lite',
        name: name,
        avatarFilename: Value('$id.png'),
        frontPorchExtensions: Value(ext),
      ),
    );
  }

  Future<void> bootGroup({int full = 2, int soft = 1}) async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-lite', name: 'The Porch'),
    );
    for (var i = 0; i < full; i++) {
      await insertMember(id: 'mem-full-$i', name: 'Full$i');
    }
    for (var i = 0; i < soft; i++) {
      await insertMember(id: 'mem-soft-$i', name: 'Soft$i', ext: _lite);
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-lite', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  CharacterCard named(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  test('create-lite-on-roster reload keeps soft + turn/Away roster', () async {
    await bootGroup();
    expect(chat.groupCharacters, hasLength(3));
    expect(named('Soft0').isLite, isTrue);
    expect(named('Full0').isLite, isFalse);

    await chat.setActiveGroup(
      GroupChat(id: 'grp-lite', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    expect(named('Soft0').isLite, isTrue);
    expect(chat.groupCharacters.map((c) => c.name), contains('Soft0'));
    chat.setNextCharacter(named('Soft0'));
    expect(chat.nextCharacter?.name, 'Soft0');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('soft is absent from feelings; 4 full + soft still tracks', () async {
    await bootGroup(full: 4, soft: 1);
    await chat.setRealismEnabled(true);
    expect(shouldTrackInterCharacterAmong(chat.groupCharacters), isTrue);

    final full0 = named('Full0');
    final soft = named('Soft0');
    final fullId = full0.stableGroupId;
    final softId = soft.stableGroupId;
    chat.relationshipService.ensureInterCharacterRelationshipsSeeded(fullId);
    chat.relationshipService.ensureInterCharacterRelationshipsSeeded(softId);

    final rels = chat.relationshipService.getInterCharacterRelationships(
      fullId,
    );
    expect(rels.containsKey(softId), isFalse);
    expect(
      chat.relationshipService.getInterCharacterRelationships(softId),
      isEmpty,
    );
    for (final other in ['Full1', 'Full2', 'Full3']) {
      expect(rels.containsKey(named(other).stableGroupId), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('promote one soft → full; others stay lite; feelings seed', () async {
    await bootGroup(full: 2, soft: 2);
    await chat.setRealismEnabled(true);
    await chat.promoteGuestToFull(named('Soft0'));

    expect(named('Soft0').isLite, isFalse);
    expect(named('Soft1').isLite, isTrue);

    final promotedId = named('Soft0').stableGroupId;
    chat.relationshipService.ensureInterCharacterRelationshipsSeeded(
      promotedId,
    );
    final rels = chat.relationshipService.getInterCharacterRelationships(
      promotedId,
    );
    expect(rels.containsKey(named('Full0').stableGroupId), isTrue);
    expect(rels.containsKey(named('Soft1').stableGroupId), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('/join --lite in a group adds a soft member', () async {
    await bootGroup(full: 2, soft: 0);
    final nora = _lib('Nora');
    await repo.addCharacter(nora);
    await chat.joinSceneGuest(nora);
    expect(chat.groupCharacters.map((c) => c.name), contains('Nora'));
    expect(named('Nora').isLite, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('1:1→group keeps present lites as soft members', () async {
    final host = _lib('Zinna');
    final guest = CharacterCard(
      name: 'Mara',
      firstMessage: 'I was already here.',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    final arrival = _lib('Senjumaru');
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await repo.addCharacter(arrival);
    await chat.setActiveCharacter(host);
    await chat.joinSceneGuest(guest);
    expect(chat.activeGroup, isNull);
    expect(chat.sceneGuestCards.map((c) => c.name), contains('Mara'));

    await chat.joinFull(arrival);

    expect(chat.activeGroup, isNotNull);
    expect(
      chat.groupCharacters.map((c) => c.name),
      containsAll(['Zinna', 'Mara', 'Senjumaru']),
    );
    expect(
      named('Mara').isLite,
      isTrue,
      reason: 'present 1:1 guest stays soft',
    );
    expect(named('Senjumaru').isLite, isFalse);
    expect(named('Zinna').isLite, isFalse);
    expect(
      chat.guestActivityStatus,
      contains('Guests stay Guest until you Promote them'),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'soft turn does not inject another member Needs/bond/objectives',
    () async {
      await bootGroup(full: 1, soft: 1);
      await chat.setRealismEnabled(true);
      await chat.setNeedsSimEnabled(true);

      const quest = 'FIND_THE_AMBER_LANTERN_QUEST';
      const starve =
          'Doubled over by a violent stomach cramp — genuinely starving';
      const soulmate = 'soulmate or life partner';

      final full0 = named('Full0');
      chat.debugSeedGroupSpeakerState(
        full0.stableGroupId,
        needs: {
          'hunger': 0,
          'bladder': 80,
          'energy': 80,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        },
        longTermTier: 7,
      );
      await chat.setObjective(quest, targetCharacter: full0);

      // Forced Soft0 pick leaves next = Full0. A null pin used to steal
      // Full0's Needs/bond; `_activeObjectives` may still hold Full0's
      // quest from group-entry load / setObjective.
      chat.setNextCharacter(named('Soft0'));
      await chat.sendMessage('What do you see?');

      final messages =
          (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
      final wire = messages.map((m) => m['content'] as String).join('\n');
      expect(wire, contains('SCENE GUEST TURN'));
      expect(wire, contains('Soft0'));
      expect(wire, isNot(contains(quest)));
      expect(wire, isNot(contains(starve)));
      expect(wire, isNot(contains(soulmate)));
      expect(wire, isNot(contains('How Full0 is right now')));
      expect(wire, isNot(contains('How Soft0 is right now')));
      expect(wire, isNot(contains('is right now:')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
