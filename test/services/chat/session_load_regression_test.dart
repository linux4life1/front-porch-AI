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

// Regression tests for the PR #162 session-load fixes, against the REAL
// ChatService + an in-memory Drift database (no fakes on the load path):
//
//  1. Per-chat generation settings must not bleed between chats — including
//     the two holes the first fix missed: entering a character with ZERO
//     sessions, and startNewChat. (Both used to keep the previous chat's
//     overrides in memory, and a fresh chat's first save could persist them.)
//  2. Retroactive sanitize ("Sanitise Existing History") rewrites MODEL
//     messages only — user and System rows must load byte-identical.

import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/models/output_sanitizer_rule.dart';
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
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

CharacterCard _card(String name, String dbId) =>
    CharacterCard(name: name)..dbId = dbId;


/// Settle fire-and-forget Drift requests inside this test's zone.
Future<void> _drainPendingDrift() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Same isolate: CI at 7cb122bf failed twice with Drift
    // "Channel was closed before receiving a response" — a background
    // isolate killed in the previous tearDown while persona load / porch
    // import was still in flight. No isolate channel, nothing to race.
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
  });

  tearDown(() async {
    chat.dispose();
    // Drain unawaited Drift work (persona _loadPersonas, porch import)
    // so it finishes on a live executor. Then close, then drain again
    // so a leftover request cannot land in the next test's zone.
    await _drainPendingDrift();
    await db.close();
    await _drainPendingDrift();
  });

  /// Seeds a session for [characterId] whose stored generation_settings
  /// carry a temperature override — the marker the tests watch for bleed.
  Future<void> seedSessionWithOverride(
    String sessionId,
    String characterId, {
    double temperature = 1.5,
  }) async {
    await db.insertSession(
      SessionsCompanion.insert(
        id: sessionId,
        characterId: Value(characterId),
        generationSettings: Value(
          ChatGenerationSettings(temperature: temperature).toJsonString(),
        ),
      ),
    );
  }

  group('per-chat generation settings bleed (PR #162 + Grok holes)', () {
    test('loading a session applies its stored overrides', () async {
      await seedSessionWithOverride('sess-a', 'char-a');
      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      expect(chat.sessionGenSettings.temperature, 1.5,
          reason: 'chat A must load its own stored override');
    });

    test('switching to a character with ZERO sessions clears overrides',
        () async {
      await seedSessionWithOverride('sess-a', 'char-a');
      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      expect(chat.sessionGenSettings.temperature, 1.5);

      // Bob has never been chatted with — the 0-session early return used
      // to keep Alice's overrides live (and Bob's first save persisted them).
      await chat.setActiveCharacter(_card('Bob', 'char-b'));
      expect(chat.sessionGenSettings.temperature, isNull,
          reason: 'fresh character must not inherit the prior chat\'s '
              'per-chat generation overrides');
    });

    test('startNewChat clears the previous session\'s overrides', () async {
      await seedSessionWithOverride('sess-a', 'char-a');
      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      expect(chat.sessionGenSettings.temperature, 1.5);

      await chat.startNewChat();
      expect(chat.sessionGenSettings.temperature, isNull,
          reason: 'a new chat with the same character starts from global '
              'defaults; only forkSession inherits overrides (by design)');
    });
  });

  group('bond scores load raw — no ±150→×2 era re-doubling', () {
    // The deleted _migrateShortTermScore wrapper doubled any |score| ≤ 150 on
    // the _loadLastSession path (library open), and _doSaveChat persisted the
    // doubled value — so every open→save cycle compounded: 40 → 80 → 160,
    // silently crossing tiers, until the score escaped the ≤150 window. The
    // history-picker path and groups never doubled (parity break). These pin
    // the fix: raw in, raw out, byte-stable across repeated open→save cycles.
    Future<int?> dbAffection(String sessionId) async {
      final row = await db
          .customSelect(
            'SELECT affection_score FROM sessions WHERE id = ?',
            variables: [Variable(sessionId)],
          )
          .getSingle();
      return row.read<int?>('affection_score');
    }

    test('open→save→reopen twice: bond 40 stays 40', () async {
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-bond',
          characterId: const Value('char-a'),
          affectionScore: const Value(40),
          longTermScore: const Value(30),
        ),
      );

      for (var cycle = 1; cycle <= 2; cycle++) {
        await chat.setActiveCharacter(_card('Alice', 'char-a'));
        expect(chat.relationshipService.affectionScore, 40,
            reason: 'cycle $cycle: library open must load the persisted bond '
                'raw (the deleted era wrapper made this 80, then 160)');
        expect(chat.relationshipService.longTermScore, 30,
            reason: 'cycle $cycle: long-term bond had the same ×2 wrapper');
        await chat.flushPendingSaves();
        expect(await dbAffection('sess-bond'), 40,
            reason: 'cycle $cycle: save must write back exactly what was '
                'loaded — this write is what made the doubling compound');
        // Switch away so the next setActiveCharacter re-runs a real load.
        await chat.setActiveCharacter(_card('Bob', 'char-b'));
      }
    });

    test('history-picker load path agrees with library open (parity)',
        () async {
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-bond2',
          characterId: const Value('char-a'),
          affectionScore: const Value(55),
          longTermScore: const Value(22),
        ),
      );

      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      final viaLibrary = chat.relationshipService.affectionScore;

      await chat.loadSession('sess-bond2');
      final viaPicker = chat.relationshipService.affectionScore;

      expect(viaLibrary, 55);
      expect(viaPicker, viaLibrary,
          reason: 'the two 1:1 load paths must produce identical scalars — '
              'pre-fix, library open doubled while the picker did not');
    });
  });

  group('shared session-scalar hydrate (refactor Step 2)', () {
    test('history-picked session restores Chaos Mode state (bug #1)',
        () async {
      // Pin: loadSession fires unawaited porch import. File setUp uses
      // sameIsolate + tearDown drains/closes so this cannot flake as
      // Drift "Channel was closed" (CI job 99190537433, twice).
      // Older session: chaos ON with built-up pressure.
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-chaos',
          characterId: const Value('char-a'),
          chaosModeEnabled: const Value(true),
          chaosPressure: const Value(42),
          createdAt: Value(DateTime(2026, 1, 1)),
          updatedAt: Value(DateTime(2026, 1, 1)),
        ),
      );
      // Newer session: chaos off — this is what the library open loads.
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-calm',
          characterId: const Value('char-a'),
          createdAt: Value(DateTime(2026, 6, 1)),
          updatedAt: Value(DateTime(2026, 6, 1)),
        ),
      );

      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      expect(chat.chaosModeService.chaosModeEnabled, isFalse,
          reason: 'library open lands on the newest session (chaos off)');

      // Resume the older chaotic session via the history picker.
      await chat.loadSession('sess-chaos');
      expect(chat.chaosModeService.chaosModeEnabled, isTrue,
          reason: 'loadSession never loaded chaos scalars pre-fix — a '
              'history-picked chat silently lost Chaos Mode');
      expect(chat.chaosModeService.chaosPressure, 42,
          reason: 'built-up Chance Time pressure must survive the picker');
    });

    test('both load paths hydrate identical scalars for the same session',
        () async {
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-full',
          characterId: const Value('char-a'),
          affectionScore: const Value(77),
          trustLevel: const Value(33),
          chaosModeEnabled: const Value(true),
          chaosPressure: const Value(9),
          characterEmotion: const Value('joy'),
        ),
      );

      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      final viaLibrary = (
        bond: chat.relationshipService.affectionScore,
        trust: chat.relationshipService.trustLevel,
        chaos: chat.chaosModeService.chaosModeEnabled,
        pressure: chat.chaosModeService.chaosPressure,
      );

      // Perturb live state, then reload the same session via the picker.
      await chat.setActiveCharacter(_card('Bob', 'char-b'));
      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      await chat.loadSession('sess-full');
      final viaPicker = (
        bond: chat.relationshipService.affectionScore,
        trust: chat.relationshipService.trustLevel,
        chaos: chat.chaosModeService.chaosModeEnabled,
        pressure: chat.chaosModeService.chaosPressure,
      );

      expect(viaLibrary, (bond: 77, trust: 33, chaos: true, pressure: 9));
      expect(viaPicker, viaLibrary,
          reason: 'the shared _hydrateSessionScalars must make the two '
              'paths byte-identical for every shared scalar');
    });
  });

  group('retroactive sanitize scope (model output only)', () {
    Future<void> seedMessage({
      required String sessionId,
      required String id,
      required int position,
      required String sender,
      required bool isUser,
      required String text,
    }) async {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: id,
          sessionId: sessionId,
          position: position,
          sender: sender,
          isUser: isUser,
          swipes: Value('["${text.replaceAll('"', r'\"')}"]'),
        ),
      );
    }

    test('hydrate rewrites AI rows, never user or System rows', () async {
      await storage.generationSettings.setOutputSanitizerEnabled(true);
      await storage.generationSettings.setSanitiseExistingHistory(true);
      await storage.generationSettings.setOutputSanitizerRules(const [
        OutputSanitizerRule(id: 0, find: 'foo', replace: 'bar'),
      ]);

      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-s',
          characterId: const Value('char-a'),
        ),
      );
      await seedMessage(
        sessionId: 'sess-s', id: 'm1', position: 0,
        sender: 'You', isUser: true, text: 'user says foo',
      );
      await seedMessage(
        sessionId: 'sess-s', id: 'm2', position: 1,
        sender: 'Alice', isUser: false, text: 'model says foo',
      );
      await seedMessage(
        sessionId: 'sess-s', id: 'm3', position: 2,
        sender: 'System', isUser: false, text: 'system says foo',
      );

      await chat.setActiveCharacter(_card('Alice', 'char-a'));

      expect(chat.messages, hasLength(3));
      expect(chat.messages[0].text, 'user says foo',
          reason: 'the user\'s own words must never be rewritten');
      expect(chat.messages[1].text, 'model says bar',
          reason: 'model output is exactly what the feature sanitizes');
      expect(chat.messages[2].text, 'system says foo',
          reason: 'System rows (backend notices) must load untouched');
    });

    test('retroactive OFF leaves even AI rows untouched on load', () async {
      await storage.generationSettings.setOutputSanitizerEnabled(true);
      await storage.generationSettings.setSanitiseExistingHistory(false);
      await storage.generationSettings.setOutputSanitizerRules(const [
        OutputSanitizerRule(id: 0, find: 'foo', replace: 'bar'),
      ]);

      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-t',
          characterId: const Value('char-a'),
        ),
      );
      await seedMessage(
        sessionId: 'sess-t', id: 'm1', position: 0,
        sender: 'Alice', isUser: false, text: 'model says foo',
      );

      await chat.setActiveCharacter(_card('Alice', 'char-a'));
      expect(chat.messages.single.text, 'model says foo',
          reason: 'sanitizer-on but retroactive-off must not rewrite '
              'already-saved history');
    });
  });
}
