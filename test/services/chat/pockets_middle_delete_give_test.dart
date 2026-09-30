// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group gift, then delete a MIDDLE (buried) give: Needs refunds every
// delete, but pockets used to rewind giver+recipients only on a tail
// delete. A buried give restored the giver via realism_state.pockets and
// left the recipient holding the unique item twice (full-codebase audit
// P0).
//
// Proven red: restore the `wasTail &&` gate on _restorePocketsFromStamp
// in deleteMessage and Sam keeps the keys.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, PocketSection;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_midgive_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String inventoryJson = '{"inventory_ops": []}';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*They nod on the porch.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('You are keeping track of what')) {
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
  _setupPathProviderMock();

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
      'journal_enabled': false,
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
    await storage.realismSettings.setPocketTransfersEnabled(true);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainUntil(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('middle-delete of a group give restores giver AND recipient', () async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-mid', name: 'Porch Duo'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-mara',
        groupId: 'grp-mid',
        name: 'Mara',
        frontPorchExtensions: Value(
          jsonEncode({
            'realism_engine': {
              'inventory': Pockets.cardJsonFrom(
                worn: const [],
                carrying: const ['car keys'],
              ),
            },
          }),
        ),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-sam',
        groupId: 'grp-mid',
        name: 'Sam',
        frontPorchExtensions: Value(
          jsonEncode({
            'realism_engine': {
              'inventory': Pockets.cardJsonFrom(
                worn: const [],
                carrying: const [],
              ),
            },
          }),
        ),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-mid', name: 'Porch Duo'),
      groupRepo: GroupChatRepository(storage, db),
    );

    String idOf(String name) {
      final c = chat.groupCharacters.firstWhere((x) => x.name == name);
      return chat.characterIdFor(c);
    }

    Pockets? kit(String name) => chat.pocketsFor(idOf(name));

    expect(kit('Mara')?.carrying.single.name, 'car keys');

    llm.inventoryJson =
        '{"inventory_ops": [{"op": "give", "item": "keys", "to": "Sam"}]}';
    await chat.sendMessage('Say goodnight to Sam.');
    await drainUntil(
      () =>
          (kit('Mara')?.carrying.isEmpty ?? false) &&
          (kit('Sam')?.carrying.any((i) => i.name == 'car keys') ?? false),
    );
    expect(kit('Sam')!.carrying.single.name, 'car keys');

    final giveIndex = chat.messages.lastIndexWhere(
      (m) => !m.isUser && m.sender != 'System',
    );
    expect(giveIndex, greaterThanOrEqualTo(0));

    // Bury the give under a later no-op turn so delete is NOT a tail delete.
    llm.inventoryJson = '{"inventory_ops": []}';
    await chat.sendMessage('Just checking.');
    await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);
    expect(chat.messages.length - 1, greaterThan(giveIndex));

    chat.deleteMessage(giveIndex);
    await drainUntil(
      () => kit('Mara')?.carrying.any((i) => i.name == 'car keys') ?? false,
    );

    expect(
      kit('Mara')?.carrying.any((i) => i.name == 'car keys') ?? false,
      isTrue,
      reason: 'giver must get the keys back when the give is deleted',
    );
    expect(
      kit('Sam')?.carrying.where((i) => i.name == 'car keys') ?? const [],
      isEmpty,
      reason: 'recipient must not keep a unique item that no longer happened',
    );
  });

  test('middle-delete of a give keeps a later unrelated pickup', () async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-mid2', name: 'Porch Duo'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-mara2',
        groupId: 'grp-mid2',
        name: 'Mara',
        frontPorchExtensions: Value(
          jsonEncode({
            'realism_engine': {
              'inventory': Pockets.cardJsonFrom(
                worn: const [],
                carrying: const ['car keys'],
              ),
            },
          }),
        ),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-sam2',
        groupId: 'grp-mid2',
        name: 'Sam',
        frontPorchExtensions: Value(
          jsonEncode({
            'realism_engine': {
              'inventory': Pockets.cardJsonFrom(
                worn: const [],
                carrying: const [],
              ),
            },
          }),
        ),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-mid2', name: 'Porch Duo'),
      groupRepo: GroupChatRepository(storage, db),
    );

    String idOf(String name) {
      final c = chat.groupCharacters.firstWhere((x) => x.name == name);
      return chat.characterIdFor(c);
    }

    Pockets? kit(String name) => chat.pocketsFor(idOf(name));

    llm.inventoryJson =
        '{"inventory_ops": [{"op": "give", "item": "keys", "to": "Sam"}]}';
    await chat.sendMessage('Say goodnight to Sam.');
    await drainUntil(
      () => kit('Sam')?.carrying.any((i) => i.name == 'car keys') ?? false,
    );
    final giveIndex = chat.messages.lastIndexWhere(
      (m) => !m.isUser && m.sender != 'System',
    );

    await chat.addPocketItem(
      idOf('Sam'),
      section: PocketSection.carrying,
      name: 'sandwich',
    );
    expect(
      kit('Sam')!.carrying.any((i) => i.name == 'sandwich'),
      isTrue,
      reason: 'sandwich must be on Sam before the give is deleted',
    );

    llm.inventoryJson = '{"inventory_ops": []}';
    await chat.sendMessage('Just checking.');
    await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

    chat.deleteMessage(giveIndex);
    await drainUntil(
      () => kit('Mara')?.carrying.any((i) => i.name == 'car keys') ?? false,
    );

    expect(
      kit('Mara')?.carrying.any((i) => i.name == 'car keys') ?? false,
      isTrue,
    );
    expect(
      kit('Sam')?.carrying.any((i) => i.name == 'car keys') ?? false,
      isFalse,
    );
    expect(
      kit('Sam')?.carrying.any((i) => i.name == 'sandwich') ?? false,
      isTrue,
      reason: 'later pickup must survive inverting the buried give',
    );
  });
}
