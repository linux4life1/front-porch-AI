// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Full Front Porch `.fpchat` cast fidelity: 1:1 scene guests and group
// soft members survive export → import on a matching open chat. Legacy
// packages without `fpai.cast` still import. Proven red: skip
// `_applyCastFromPackage` (1:1 guests stay wiped) or omit `tier: lite`
// then promote-before-import (group soft stays full).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_cast_rt_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';
const _lite = '{"version":"2.5","realism_engine":{"tier":"lite"}}';

CharacterCard _lib(String name) => CharacterCard(
  name: name,
  firstMessage: 'Hello from $name.',
  personality: '$name personality',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late UserPersonaService personas;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    personas = UserPersonaService(db);
    chat =
        ChatService(
            KoboldService(storage),
            personas,
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..setGroupChatRepository(GroupChatRepository(storage, db));
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> insertMember({
    required String id,
    required String name,
    String ext = _off,
  }) async {
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: id,
        groupId: 'grp-cast',
        name: name,
        avatarFilename: Value('$id.png'),
        frontPorchExtensions: Value(ext),
      ),
    );
  }

  Future<void> bootGroup() async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-cast', name: 'Cast Porch'),
    );
    await insertMember(id: 'mem-full-0', name: 'Full0');
    await insertMember(id: 'mem-soft-0', name: 'Soft0', ext: _lite);
    await chat.setActiveGroup(
      GroupChat(id: 'grp-cast', name: 'Cast Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  CharacterCard named(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  List<FpchatCastMember> castOf(Uint8List zip) {
    final root = decodeFpchatBytes(zip).chatJson;
    final fpai = Map<String, dynamic>.from(root['fpai'] as Map);
    expect(fpai['stamp_version'], kFpchatStampVersion);
    return parseFpchatCast(fpai[kFpchatCastKey]);
  }

  test('group soft + full export/import keeps lite and attribution', () async {
    await bootGroup();
    expect(named('Soft0').isLite, isTrue);
    final softId = named('Soft0').stableGroupId;
    chat.debugSeedTranscriptForFpchat([
      ChatMessage(text: 'hey', sender: 'User', isUser: true),
      ChatMessage(
        text: 'soft wave',
        sender: 'Soft0',
        isUser: false,
        characterId: softId,
      ),
    ]);

    final zip = await chat.exportToFpchat();
    expect(zip, isNotNull);
    final exported = castOf(zip!);
    expect(exported.where((e) => e.lite).map((e) => e.name), contains('Soft0'));
    expect(
      exported.where((e) => !e.lite).map((e) => e.name),
      contains('Full0'),
    );

    await chat.promoteGuestToFull(named('Soft0'));
    expect(named('Soft0').isLite, isFalse);

    final result = await chat.importChatPackage(zip);
    expect(result.fullRestore, isTrue);
    expect(named('Soft0').isLite, isTrue);
    expect(named('Full0').isLite, isFalse);
    expect(chat.messages.where((m) => !m.isUser).single.characterId, softId);
  });

  test('1:1 scene guest export/import restores the guest list', () async {
    final host = _lib('Zinna');
    final guest = _lib('Mara');
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await chat.startFreshChatWith(
      character: host,
      personaId: personas.persona.id,
    );
    await chat.debugEnterSceneGuestSilent(guest);
    expect(chat.sceneGuestCards.map((c) => c.name), contains('Mara'));

    final zip = await chat.exportToFpchat();
    expect(zip, isNotNull);
    final exported = castOf(zip!);
    expect(exported.single.name, 'Mara');
    expect(exported.single.lite, isTrue);

    final result = await chat.importChatPackage(zip);
    expect(result.fullRestore, isTrue);
    expect(chat.sceneGuestCards.map((c) => c.name), contains('Mara'));
    expect(chat.sceneGuestCards, hasLength(1));
  });

  test('legacy package without cast still imports', () async {
    final host = _lib('Zinna');
    await repo.addCharacter(host);
    await chat.startFreshChatWith(
      character: host,
      personaId: personas.persona.id,
    );
    final zip = encodeFpchatZip(
      chatJson: {
        'format': kFpchatFormatId,
        'version': kFpchatFormatVersion,
        'messages': [
          {'name': 'User', 'is_user': true, 'mes': 'hi'},
          {'name': 'Zinna', 'is_user': false, 'mes': 'hey'},
        ],
        'fpai': {
          'version': 1,
          'kind': 'timeline',
          'stamp_version': 1,
          'character': {'name': 'Zinna', 'stable_group_id': host.stableGroupId},
          'session': {'realism_enabled': false, 'needs_sim_enabled': false},
          'messages_extra': [],
        },
      },
    );
    final result = await chat.importChatPackage(zip);
    expect(result.fullRestore, isTrue);
    expect(chat.sceneGuestCards, isEmpty);
    expect(chat.messages, hasLength(2));
  });
}
