// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-character Pockets & Wardrobe AND-gate.
//
// Global off is the master kill. Global on + missing/null card flag stays on
// (old cards). Global on + explicit card off disables that character only —
// pocketsFor hides, seed does not plant, add-by-hand no-ops. A group member
// uses their own group-copy flag; another member in the same chat stays on.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, PocketSection;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db)
      ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  CharacterCard card(
    String name,
    String id, {
    bool? pocketsEnabled,
    bool dressed = true,
  }) {
    return CharacterCard(
      name: name,
      firstMessage: 'Hi.',
      frontPorchExtensions: FrontPorchExtensions(
        pocketsEnabled: pocketsEnabled ?? true,
        inventory: dressed
            ? Pockets.cardJsonFrom(
                worn: const ['linen shirt'],
                carrying: const ['house keys'],
              )
            : const {},
      ),
    )..dbId = id;
  }

  Pockets? sees(CharacterCard c) => chat.pocketsFor(chat.characterIdFor(c));

  test('default-on card seeds and shows when the global is on', () async {
    final c = card('Ana', 'char-on');
    await chat.setActiveCharacter(c);

    expect(chat.pocketsEnabledFor(chat.characterIdFor(c)), isTrue);
    expect(sees(c), isNotNull);
    expect(sees(c)!.carrying.map((i) => i.name), contains('house keys'));
  });

  test(
    'explicit-off card hides and does not seed when the global is on',
    () async {
      final c = card('Bea', 'char-off', pocketsEnabled: false);
      await chat.setActiveCharacter(c);

      expect(
        chat.pocketsEnabledFor(chat.characterIdFor(c)),
        isFalse,
        reason: 'global on + card off → this character only',
      );
      expect(
        sees(c),
        isNull,
        reason: 'pocketsFor must hide — same as the global-off read gate',
      );
      await chat.addPocketItem(
        chat.characterIdFor(c),
        section: PocketSection.carrying,
        name: 'lucky coin',
      );
      expect(
        sees(c),
        isNull,
        reason: 'add-by-hand must no-op when this character has Pockets off',
      );
    },
  );

  test('global off is a master kill even when the card flag is on', () async {
    final c = card('Cara', 'char-global-off');
    await storage.realismSettings.setPocketsEnabled(false);
    await chat.setActiveCharacter(c);

    expect(chat.pocketsFeatureEnabled, isFalse);
    expect(chat.pocketsEnabledFor(chat.characterIdFor(c)), isFalse);
    expect(sees(c), isNull);
  });

  test(
    'group members use their own flag — one off does not silence the other',
    () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-pw', name: 'The Porch'),
      );
      Future<void> insertMember({
        required String id,
        required String name,
        required bool pocketsOn,
      }) {
        return db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: id,
            groupId: 'grp-pw',
            name: name,
            frontPorchExtensions: Value(
              jsonEncode(
                FrontPorchExtensions(
                  pocketsEnabled: pocketsOn,
                  inventory: Pockets.cardJsonFrom(
                    worn: const ['linen shirt'],
                    carrying: const ['house keys'],
                  ),
                ).toJson(),
              ),
            ),
          ),
        );
      }

      await insertMember(id: 'mem-on', name: 'Ana', pocketsOn: true);
      await insertMember(id: 'mem-off', name: 'Bea', pocketsOn: false);

      await chat.setActiveGroup(
        GroupChat(id: 'grp-pw', name: 'The Porch'),
        groupRepo: GroupChatRepository(storage, db),
      );

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
      final anaId = chat.characterIdFor(ana);
      final beaId = chat.characterIdFor(bea);

      expect(chat.pocketsEnabledFor(anaId), isTrue);
      expect(chat.pocketsEnabledFor(beaId), isFalse);
      expect(chat.pocketsFor(anaId), isNotNull, reason: 'Ana stays dressed');
      expect(
        chat.pocketsFor(beaId),
        isNull,
        reason: 'Bea authored off — her group copy must not seed or show',
      );
    },
  );
}
