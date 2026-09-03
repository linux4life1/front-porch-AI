// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Converting a 1:1 into a group must copy the host's LIVE pockets onto the
// host member — the inverse of collapse, which writes `_pockets = solePockets`.
// Fork captured realism, flags, journal, rings, and quests, then
// setActiveGroup cleared the 1:1 `_pockets` scalar and never planted it on
// the member. She walked in empty-handed.
//
// Proven red: skip the setPocketsFor apply in _carryHostStateIntoForkedGroup
// and the keys/apron assertions fail.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

final Directory _root = Directory.systemTemp.createTempSync(
  'fpai_forkpockets_',
);

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return _root.path;
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
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'pockets_enabled': true,
    });
    db = await AppDatabase.instance();
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

  tearDown(() {
    chat.dispose();
  });

  CharacterCard card(String name, String id) => CharacterCard(
    name: name,
    description: 'Exists only inside the fork-pockets test.',
    firstMessage: 'The screen door bangs shut behind you.',
  )..dbId = id;

  test(
    'forking a 1:1 into a group carries the host pockets onto the member',
    () async {
      final host = card('Nia', 'char-pockets-host');
      await chat.setActiveCharacter(host);
      chat.setPocketsFor(
        host.stableGroupId,
        Pockets(
          worn: [const PocketItem('flour-dusted apron')],
          carrying: [const PocketItem('car keys')],
        ),
      );

      final group = await chat.forkToGroupChat([
        card('Marisol', 'char-pockets-arrival'),
      ], GroupChatRepository(storage, db));
      expect(group, isNotNull, reason: 'the conversion itself must succeed');

      final hostMember = chat.groupCharacters.firstWhere(
        (c) => c.name == 'Nia',
      );
      final carried = chat.pocketsFor(hostMember.stableGroupId);
      expect(
        carried,
        isNotNull,
        reason:
            'THE BUG: setActiveGroup cleared the 1:1 scalar and the fork '
            'never planted it on the host member',
      );
      expect(carried!.carrying.map((i) => i.name), contains('car keys'));
      expect(carried.worn.map((i) => i.name), contains('flour-dusted apron'));
    },
  );
}
