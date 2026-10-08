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

// #328 — "Default Persona is not working".
//
// Switch persona inside a chat ("Use in this chat"), go back to the library
// and LEFT-click a character that has never been opened. That is
// setActiveCharacter with no stored session: _loadLastSession finds nothing,
// so _activateSessionPersona never runs, and before the fix nothing else on
// that path reset the active persona either. The previous chat's persona
// stayed live, the greeting's {{user}} resolved as them, and the greeting's
// _saveChat bound the brand-new session to them for good. Right-click → New
// Chat was fine because startNewChat already resets to the default.
//
// Deliberately NO startNewChat call before the tap — that is the bug. The
// group tests are the same flow through setActiveGroup. The last 1:1 test pins
// the `_currentSessionId == null` guard: a stored zero-message chat also takes
// the fresh-chat branch, and it must keep the persona it was bound to.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_freshpersona_').path;
        }
        return null;
      });
}

class _InertLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'InertLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late UserPersonaService personas;
  late ChatService chat;
  late String porchy;
  late String nightowl;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
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
          ..testLlmServiceOverride = _InertLlm();
    await storage.initialized;

    await personas.createPersona('', 'Porchy', 'Sits on the steps.', null);
    porchy = personas.persona.id;
    // Persona ids are epoch-millis — space the second one out.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await personas.createPersona('', 'Nightowl', 'Up too late.', null);
    nightowl = personas.persona.id;
    expect(nightowl, isNot(porchy));
    // Step 1 of the report: Porchy is the default.
    await personas.setDefaultPersona(porchy);
    await personas.setActivePersona(porchy);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<CharacterCard> seed(String name) async {
    final card = CharacterCard(
      name: name,
      description: 'Persona-default (#328) test card.',
      firstMessage: 'Evening, {{user}}. Pull up a chair.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await repo.addCharacter(card);
    return card;
  }

  /// Steps 2–3: open a chat, then switch it to Nightowl the way the
  /// "Speak as…" dialog does (setActivePersona + persistSessionPersona).
  /// Returns that chat's session id.
  Future<String> chatThenSwitchToNightowl(CharacterCard card) async {
    await chat.setActiveCharacter(card);
    await chat.sendMessage('Still me, still here.');
    final id = chat.currentSessionId!;
    await personas.setActivePersona(nightowl);
    await chat.persistSessionPersona();
    expect((await db.getSessionById(id))!.userPersonaId, nightowl);
    expect(personas.persona.id, nightowl);
    expect(personas.defaultPersonaId, porchy);
    return id;
  }

  Future<void> seedGroup(String id) async {
    await db.insertGroup(GroupsCompanion.insert(id: id, name: 'The Porch'));
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: '$id-mem',
        groupId: id,
        name: 'Evelyn',
        // A greeting, so the fresh group actually mints and SAVES a session.
        firstMessage: const Value('Evening, {{user}}. The screen door bangs.'),
        avatarFilename: Value('$id-mem.png'),
      ),
    );
  }

  Future<void> enterGroup(String id) => chat.setActiveGroup(
    GroupChat(id: id, name: 'The Porch'),
    // The no-repo fallback reads the AppDatabase singleton, not this test's
    // in-memory database, and would resolve no members.
    groupRepo: GroupChatRepository(storage, db),
  );

  test('left-clicking a NEVER-opened character starts as the default persona, '
      'not the previous chat\'s in-chat persona', () async {
    final first = await seed('Porch Sitter');
    final second = await seed('Late Riser');
    final firstSessionId = await chatThenSwitchToNightowl(first);

    // Step 4: left-click a character with no chats. No startNewChat.
    await chat.setActiveCharacter(second);

    final freshId = chat.currentSessionId;
    expect(freshId, isNotNull);
    expect(freshId, isNot(firstSessionId));
    expect(
      personas.persona.id,
      porchy,
      reason:
          'THE BUG (#328): the no-session path never reset the persona, so '
          'Nightowl from the previous chat leaked into the new one',
    );
    expect(
      (await db.getSessionById(freshId!))!.userPersonaId,
      porchy,
      reason: 'the greeting save must bind the new chat to the default',
    );
    expect(
      chat.messages.first.text,
      contains('Porchy'),
      reason: 'the greeting {{user}} must resolve as the default too',
    );
    expect(personas.defaultPersonaId, porchy);

    // And the chat that was switched keeps its own persona.
    await chat.setActiveCharacter(first);
    expect(personas.persona.id, nightowl);
    expect((await db.getSessionById(firstSessionId))!.userPersonaId, nightowl);
  });

  test('a stored ZERO-message chat keeps its own persona (the '
      '_currentSessionId == null guard)', () async {
    final first = await seed('Porch Sitter');
    final second = await seed('Late Riser');
    // A saved chat for `second` with no messages, bound to Nightowl. It goes
    // through the same fresh-chat branch (messages empty) but a row WAS
    // loaded, so its binding must win over the default.
    const storedId = '1000';
    final now = DateTime.now();
    await db.insertSession(
      SessionsCompanion.insert(
        id: storedId,
        characterId: Value(second.dbId),
        userPersonaId: Value(nightowl),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    // Previous chat is under the default, so a leak would be invisible —
    // the point here is that the default must NOT overwrite Nightowl.
    await chat.setActiveCharacter(first);
    await chat.sendMessage('hello');
    expect(personas.persona.id, porchy);

    await chat.setActiveCharacter(second);

    // (The fresh-chat branch then mints a new session id for the greeting —
    // pre-existing behaviour, untouched here. What matters is the persona.)
    expect(
      personas.persona.id,
      nightowl,
      reason: 'an existing zero-message chat keeps the persona it was bound to',
    );
    expect((await db.getSessionById(storedId))!.userPersonaId, nightowl);
    expect(
      (await db.getSessionById(chat.currentSessionId!))!.userPersonaId,
      nightowl,
      reason: 'and the greeting save carries that persona, not the default',
    );
  });

  test('entering a NEVER-opened group starts as the default persona, not the '
      'previous chat\'s in-chat persona', () async {
    final first = await seed('Porch Sitter');
    final firstSessionId = await chatThenSwitchToNightowl(first);
    await seedGroup('grp-fresh');

    await enterGroup('grp-fresh');

    final freshId = chat.currentSessionId;
    expect(chat.groupCharacters, hasLength(1));
    expect(freshId, isNotNull);
    expect(freshId, isNot(firstSessionId));
    expect(
      personas.persona.id,
      porchy,
      reason: 'group twin of #328: Nightowl must not leak into a new group',
    );
    final row = (await db.getSessionById(freshId!))!;
    expect(row.groupId, 'grp-fresh');
    expect(row.userPersonaId, porchy);
    expect(chat.messages.first.text, contains('Porchy'));
    expect(personas.defaultPersonaId, porchy);
    expect((await db.getSessionById(firstSessionId))!.userPersonaId, nightowl);
  });

  test('re-entering a group restores ITS persona, not the default', () async {
    await seedGroup('grp-kept');
    await enterGroup('grp-kept');
    final groupSessionId = chat.currentSessionId!;
    await personas.setActivePersona(nightowl);
    await chat.persistSessionPersona();

    final first = await seed('Porch Sitter');
    await chat.setActiveCharacter(first);
    expect(personas.persona.id, porchy);

    await enterGroup('grp-kept');
    expect(chat.currentSessionId, groupSessionId);
    expect(
      personas.persona.id,
      nightowl,
      reason: 'the reset is for brand-new groups only',
    );
  });
}
