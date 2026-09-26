// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// "Start New Chat" from the home grid's card menus (desktop context menu and
// the web library both route through ChatService.startFreshChatWith), against
// the REAL ChatService + an in-memory Drift database.
//
// The invariant under test is an ORDERING one and it is easy to get wrong:
// entering a cast loads its most recent session, and loading a session
// restores THAT session's persona. So a chosen persona applied before entry
// is silently clobbered by the previous chat's. These tests seed a prior
// session under one persona and start fresh under another.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat_service.dart';
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
  late UserPersonaService personas;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    // Let the persona service finish seeding its default persona.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  /// Two personas: the one a previous chat used, and the one the user picks
  /// in the dialog. Returns (previous, chosen) ids.
  Future<(String previous, String chosen)> seedTwoPersonas() async {
    await personas.createPersona('The Detective', 'Sam', 'A tired PI.', null);
    final previous = personas.persona.id;
    await personas.createPersona('The Baker', 'Robin', 'Flour-dusted.', null);
    final chosen = personas.persona.id;
    expect(previous, isNot(chosen));
    return (previous, chosen);
  }

  test(
    'the chosen persona survives entry (which restores the old one)',
    () async {
      final (previous, chosen) = await seedTwoPersonas();

      // A prior chat with this character, recorded under the OTHER persona.
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-old',
          characterId: const Value('char-a'),
          userPersonaId: Value(previous),
        ),
      );

      await chat.startFreshChatWith(
        character: CharacterCard(name: 'Misty')..dbId = 'char-a',
        personaId: chosen,
      );

      // If the persona were applied before setActiveCharacter, loading
      // 'sess-old' would have reset it to `previous`.
      expect(personas.persona.id, chosen);
      // And it really is a fresh session, not the one we seeded.
      expect(chat.currentSessionId, isNot('sess-old'));
      expect(chat.currentSessionId, isNotNull);
    },
  );

  test('the fresh session stores the chosen persona', () async {
    final (previous, chosen) = await seedTwoPersonas();
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-old',
        characterId: const Value('char-b'),
        userPersonaId: Value(previous),
      ),
    );

    await chat.startFreshChatWith(
      // A greeting gives the fresh chat a message: ChatService deliberately
      // skips persisting an EMPTY session ("protect existing data"), so a
      // greeting-less card would never write a row here.
      character: CharacterCard(name: 'Rook', firstMessage: 'Evening.')
        ..dbId = 'char-b',
      personaId: chosen,
    );
    // Persist, then read the row back the way a later resume would.
    await chat.flushPendingSaves();

    final row = await db.getSessionById(chat.currentSessionId!);
    expect(row?.userPersonaId, chosen);
  });

  test('an empty persona id leaves the active persona alone', () async {
    final (_, chosen) = await seedTwoPersonas();

    await chat.startFreshChatWith(
      character: CharacterCard(name: 'Misty')..dbId = 'char-c',
      personaId: '',
    );

    // No choice supplied → whatever was active stays active (the caller
    // cancelled out of the picker, or personas aren't in play at all).
    expect(personas.persona.id, chosen);
  });

  test('no character and no group is a no-op', () async {
    await chat.startFreshChatWith(personaId: 'whatever');
    expect(chat.currentSessionId, isNull);
  });
}
