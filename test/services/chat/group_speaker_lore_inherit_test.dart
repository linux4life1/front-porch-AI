// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Group turns inject the speaking card's character lorebook, plus
// group/world lore — not other members' "Present scene" rows.
// Constant lore sits after history (not in the system head) so a
// trigger cannot bust prefix cache. Proven red: restore inherit-all
// member books in _collectLoreRefs and Zinna's turn contains
// SENJUMARU_PRESENT_SCENE_MARKER.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lore_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';
const kSenjuScene =
    'SENJUMARU_PRESENT_SCENE_MARKER Present scene: Living World riverside path';
const kZinnaScene = 'ZINNA_PRESENT_SCENE_MARKER porch dusk';

({String system, String user}) _wire(FakeBackendServer backend) {
  final messages =
      (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
  return (
    system: messages.first['content'] as String,
    user: messages.last['content'] as String,
  );
}

String _constLore(String content) => jsonEncode(
  Lorebook(
    entries: [LorebookEntry(content: content, constant: true, name: content)],
  ).toJson(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['She looks toward the porch rail.'],
    );
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
          ..setCharacterRepository(CharacterRepository(db, storage))
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

  Future<void> bootGroup() async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-lore', name: 'The Cast'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-zinna-lore',
        groupId: 'grp-lore',
        name: 'Zinna',
        personality: const Value('ZINNA_PERSONA_MARKER porch host'),
        avatarFilename: const Value('zinna.png'),
        lorebook: Value(_constLore(kZinnaScene)),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-senju-lore',
        groupId: 'grp-lore',
        name: 'Senjumaru',
        personality: const Value('SENJUMARU_PERSONA_MARKER thousand arms'),
        avatarFilename: const Value('senju.png'),
        lorebook: Value(_constLore(kSenjuScene)),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-lore', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  test("Zinna's turn does not ingest Senjumaru present-scene lore", () async {
    await bootGroup();
    chat.setNextCharacter(member('Zinna'));
    await chat.sendMessage('Good evening.');

    final w = _wire(backend);
    expect(w.system, isNot(contains(kZinnaScene)));
    expect(w.user, contains(kZinnaScene));
    expect(w.user, isNot(contains(kSenjuScene)));
    expect(w.system, isNot(contains(kSenjuScene)));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("Senjumaru's turn may inject her own present-scene lore", () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.system, isNot(contains(kSenjuScene)));
    expect(w.user, contains(kSenjuScene));
    expect(w.system, isNot(contains(kZinnaScene)));
    expect(w.user, isNot(contains(kZinnaScene)));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
