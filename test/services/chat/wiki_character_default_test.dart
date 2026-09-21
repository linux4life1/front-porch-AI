// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Picking a wiki in a 1:1 chat stores a per-character default; a new 1:1
// with that character seeds this chat from it. Groups do not guess.
//
// Guard proven red: omitting _seedWikiForNewSession left the new session
// on the Porch Life default.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_wiki_char_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late UserPersonaService personas;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  test('new 1:1 chat uses the wiki picked for that character', () async {
    await storage.webSearchSettings.addSavedWikiUrl(
      'https://bleach.fandom.com/',
    );
    await storage.webSearchSettings.addSavedWikiUrl(
      'https://onepunchman.fandom.com/',
    );

    final sophia = CharacterCard(name: 'Sophia', firstMessage: 'Hi.')
      ..dbId = 'char-sophia';
    final mirin = CharacterCard(name: 'Mirin', firstMessage: 'Yo.')
      ..dbId = 'char-mirin';

    await chat.startFreshChatWith(character: sophia, personaId: '');
    await chat.setWikiBaseUrl('https://bleach.fandom.com/');
    expect(
      storage.webSearchSettings.wikiUrlForChat(chat.currentSessionId),
      'https://bleach.fandom.com',
    );
    expect(
      storage.webSearchSettings.wikiUrlForCharacter(sophia.stableGroupId),
      'https://bleach.fandom.com',
    );

    await chat.startFreshChatWith(character: mirin, personaId: '');
    await chat.setWikiBaseUrl('https://onepunchman.fandom.com/');

    await chat.startFreshChatWith(character: sophia, personaId: '');
    expect(chat.wikiBaseUrl, 'https://bleach.fandom.com');

    await chat.startFreshChatWith(character: mirin, personaId: '');
    expect(chat.wikiBaseUrl, 'https://onepunchman.fandom.com');
  });
}
