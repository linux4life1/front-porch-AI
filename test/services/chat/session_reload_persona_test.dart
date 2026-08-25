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

// A SAME-session reload must READ the row, never write it first (2026-08-13).
//
// 6192ddc's per-turn-persist work put an unconditional flushPendingSaves()
// at the top of loadSession. flush is a FULL save, so reloading the session
// that is already open stamped the live scalars — the active persona above
// all — onto the row before the restore read it back: switch persona, reopen
// the chat, and it "restores" the persona you just switched to, durably
// rewriting the session's binding. That is exactly the flow of the
// persona_default / persona_folder E2Es (red on every platform since
// 6192ddc) — this is their fast unit twin, red before the gate and green
// with it.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_perload_').path;
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
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  test('reloading the OPEN session restores its persona instead of stamping '
      'the live one onto the row', () async {
    // Two personas; creating one makes it active+default, so Porchy first —
    // the chat is seeded under Porchy — then Nightowl takes over as the
    // live persona, exactly like the E2E's "move the default" step.
    await personas.createPersona('Porchy', 'Porchy', 'porch tester', null);
    final porchy = personas.persona.id;
    // Persona ids are epoch-millis — space the second one out.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final card = CharacterCard(
      name: 'Sitter',
      description: 'Persona-reload test card.',
      firstMessage: 'The porch light hums.',
    );
    await repo.addCharacter(card);
    await chat.setActiveCharacter(card);
    await chat.sendMessage('hold my persona');
    final sessionId = chat.currentSessionId!;

    // The row is bound to Porchy.
    expect((await db.getSessionById(sessionId))!.userPersonaId, porchy);

    await personas.createPersona('Nightowl', 'Nightowl', 'late shift', null);
    final nightowl = personas.persona.id;
    expect(nightowl, isNot(porchy));

    // Reopen the SAME session — the picker flow. The row must win.
    await chat.loadSession(sessionId);

    expect(
      personas.persona.id,
      porchy,
      reason: 'reopening a chat restores the persona it was chatted under',
    );
    expect(
      (await db.getSessionById(sessionId))!.userPersonaId,
      porchy,
      reason:
          'the reload must not have rewritten the row binding first — '
          'that is the write-before-read bug this suite pins',
    );
  });

  // Matches persona_default_test E2E step 4: setActiveCharacter(first) then
  // loadSession(A). The same-session pin above never hydrates via
  // _loadLastSession while Nightowl is live, so it stays green if only
  // loadSession's flush gate is correct.
  test(
    'setActiveCharacter then loadSession restores Porchy after a Nightowl new chat',
    () async {
      await personas.createPersona('Porchy', 'Porchy', 'porch tester', null);
      final porchy = personas.persona.id;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await personas.createPersona('Nightowl', 'Nightowl', 'late shift', null);
      final nightowl = personas.persona.id;
      expect(nightowl, isNot(porchy));
      await personas.setDefaultPersona(porchy);
      await personas.setActivePersona(porchy);

      Future<CharacterCard> seed(String name) async {
        final card = CharacterCard(
          name: name,
          description: 'E2E-twin persona card.',
          firstMessage: 'Evening. Pull up a chair.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        );
        await repo.addCharacter(card);
        return card;
      }

      final first = await seed('Porch Sitter');
      final second = await seed('Late Riser');

      await chat.setActiveCharacter(first);
      await chat.startNewChat();
      await chat.sendMessage('Still me, still here.');
      final firstSessionId = chat.currentSessionId!;
      expect((await db.getSessionById(firstSessionId))!.userPersonaId, porchy);
      expect(personas.persona.id, porchy);

      await personas.setDefaultPersona(nightowl);
      expect(personas.persona.id, porchy);
      expect(personas.defaultPersonaId, nightowl);

      await chat.setActiveCharacter(second);
      await chat.startNewChat();
      expect(personas.persona.id, nightowl);
      expect(personas.defaultPersonaId, nightowl);

      expect(
        (await db.getSessionById(firstSessionId))!.userPersonaId,
        porchy,
        reason: 'Nightowl new chat must not have rewritten chat A',
      );

      await chat.setActiveCharacter(first);
      // Same write _loadLastSession overlay-reapply / flushPendingSaves can
      // do after setting _currentSessionId while Nightowl is still live.
      await chat.flushPendingSaves();
      expect(
        (await db.getSessionById(firstSessionId))!.userPersonaId,
        porchy,
        reason:
            '_loadLastSession hydrate must not stamp live Nightowl onto chat A',
      );

      await chat.loadSession(firstSessionId);
      expect(
        personas.persona.id,
        porchy,
        reason:
            'setActiveCharacter then loadSession must restore chat A\'s Porchy',
      );
      expect(
        personas.defaultPersonaId,
        nightowl,
        reason: 'reopening a chat must not drag the default back',
      );
      expect((await db.getSessionById(firstSessionId))!.userPersonaId, porchy);
    },
  );

  // persona_default_test E2E step 4 + home_page_history _openHistorySession:
  // setActiveCharacter(first) then loadSession(A), no flush in between.
  // The service twin above inserts flushPendingSaves and stays green while
  // the sandboxed E2E still times out on Nightowl. This is that reopen.
  test(
    'history reopen setActiveCharacter then loadSession restores Porchy with no flush',
    () async {
      await personas.createPersona('', 'Porchy', 'Sits on the steps.', null);
      final porchy = personas.persona.id;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await personas.createPersona('', 'Nightowl', 'Up too late.', null);
      final nightowl = personas.persona.id;
      expect(nightowl, isNot(porchy));
      await personas.setDefaultPersona(porchy);
      await personas.setActivePersona(porchy);

      Future<CharacterCard> seed(String name) async {
        final card = CharacterCard(
          name: name,
          description: 'Exists only inside the persona-default E2E.',
          firstMessage: 'Evening. Pull up a chair.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        );
        await repo.addCharacter(card);
        return card;
      }

      final first = await seed('Porch Sitter');
      final second = await seed('Late Riser');

      await chat.setActiveCharacter(first);
      await chat.startNewChat();
      await chat.sendMessage('Still me, still here.');
      final firstSessionId = chat.currentSessionId!;
      expect((await db.getSessionById(firstSessionId))!.userPersonaId, porchy);
      expect(
        (await db.getSessionById(firstSessionId))!.characterId,
        first.dbId,
      );

      await personas.setDefaultPersona(nightowl);
      expect(personas.persona.id, porchy);

      await chat.setActiveCharacter(second);
      await chat.startNewChat();
      expect(personas.persona.id, nightowl);

      final afterNightowl = await db.getSessionById(firstSessionId);
      expect(
        afterNightowl!.userPersonaId,
        porchy,
        reason: 'Nightowl New Chat must not stamp chat A',
      );
      expect(
        afterNightowl.characterId,
        first.dbId,
        reason: 'Nightowl New Chat must not rebind chat A onto Late Riser',
      );

      await chat.setActiveCharacter(first);
      expect(
        personas.persona.id,
        porchy,
        reason:
            '_loadLastSession (library / last-session path) must restore Porchy',
      );

      await chat.loadSession(firstSessionId);
      expect(
        personas.persona.id,
        porchy,
        reason:
            'history reopen (setActiveCharacter then loadSession, no flush) '
            'must restore chat A\'s Porchy',
      );
      expect(personas.defaultPersonaId, nightowl);
      expect((await db.getSessionById(firstSessionId))!.userPersonaId, porchy);
    },
  );
}
