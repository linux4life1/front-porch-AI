// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where are the keys?" has one answer. When a group speaker picks an item
// up, every placement card about it in this chat retires — not only the
// speaker's own. Ana set the keys down; Bea picks them up; Ana's diary must
// stop saying they are on the table.
//
// Real ChatService, real Drift database, a real post-gen pockets pass. The
// scripted model only stages the pickup op; the assertion reads the diary.
//
// Proven red: in _writeItemCards, route the pickup retire through
// _retireItemCardsFor(ownerId, item) (speaker only) instead of
// retireItemCardsInSession → the other member's card survives.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import '../../helpers/chat_db_teardown.dart';

class _ScriptedLlm extends LLMService {
  String inventoryJson = '{"inventory_ops": []}';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*They scoop the keys off the porch table.*';
      return;
    }
    if (params.prompt.contains('You are keeping track of what')) {
      yield inventoryJson;
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pickup_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': true,
      'journal_enabled': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> insertMember(String id, String name) => db.insertGroupMember(
    GroupMembersCompanion.insert(
      id: id,
      groupId: 'grp-keys',
      name: name,
      frontPorchExtensions: Value(
        jsonEncode(
          FrontPorchExtensions(
            pocketsEnabled: true,
            inventory: Pockets.cardJsonFrom(worn: const [], carrying: const []),
          ).toJson(),
        ),
      ),
    ),
  );

  Future<List<JournalMemoryData>> keyCards() async {
    final cards = await db.getJournalCardsForSession(chat.currentSessionId!);
    return cards
        .where(
          (c) =>
              JournalPhysics.isItemCard(c) &&
              JournalPhysics.itemOf(c) == 'car keys',
        )
        .toList();
  }

  test('a pickup retires every member\'s card about that item', () async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-keys', name: 'The Porch'),
    );
    await insertMember('mem-ana', 'Ana');
    await insertMember('mem-bea', 'Bea');
    await chat.setActiveGroup(
      GroupChat(id: 'grp-keys', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.flushPendingSaves();

    final store = JournalStore(getDb: () => db);
    for (final m in chat.groupCharacters) {
      await store.addCard(
        sessionId: chat.currentSessionId!,
        characterId: chat.characterIdFor(m),
        content: '${m.name} set the car keys down on the porch table.',
        category: 'item',
        kind: 'item',
        extraMetadata: {'item': 'car keys'},
        maxCards: 200,
      );
    }
    expect(await keyCards(), hasLength(2), reason: 'precondition');

    llm.inventoryJson =
        '{"inventory_ops": [{"op": "pickup", "item": "car keys"}]}';
    await chat.sendMessage('Grab the keys, would you?');
    for (var i = 0; i < 600; i++) {
      if (!chat.isGenerating &&
          !chat.isSettlingTurn &&
          (await keyCards()).length < 2) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await chat.flushPendingSaves();

    final speaker = chat.messages.last.sender;
    final carrier = chat.groupCharacters.firstWhere((c) => c.name == speaker);
    expect(
      chat
          .pocketsFor(chat.characterIdFor(carrier))
          ?.carrying
          .map((i) => i.name),
      contains('car keys'),
      reason: 'the pickup applied to the speaker',
    );
    expect(
      (await keyCards()).map((c) => c.content),
      isEmpty,
      reason: 'the other member\'s placement card is stale once picked up',
    );
  });
}
