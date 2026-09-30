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

// THE PROMISE PASS JOINS THE EVAL DIET (2026-08-10). The Promise Ledger
// built its own inline 6-message window from raw displayText — the one
// turn-adjacent window the diet missed — and the maintainer's EvalTraffic
// line caught it: `promise(text) 38.3k→59`, thirty-eight thousand chars of
// prompt for a 59-char verdict, all novella re-reading. It now rides
// recentExchange (per-message clamp + photo markers + think-strip).
//
// This drives the REAL ChatService with a scripted LLM: the reply is a 21k
// novella whose TAIL carries the promise ("I promise to call you at noon
// tomorrow"), so the test also proves the clamp's head+tail shape keeps the
// commitment visible to warrantsEval and the model — a clamp that ate the
// tail would silently kill promise detection for verbose models.
//
// Guard proven to fail before passing: reverting the window to the old
// inline uncapped builder sends the marker/length assertions red (the
// prompt carries the full novella again).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kEvalClampMarker, kEvalMessageCharCap;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_promise_').path;
        }
        return null;
      });
}

/// 21k chars of reply with the commitment at the very end — the tail the
/// clamp must preserve.
final String _novellaWithPromise =
    '*She rocks slowly and talks about the garden. '
    '${'The porch boards creak under the runners as the evening light moves '
            'through the screen door, unhurried and warm. ' * 180}'
    'Then she looks up.* I promise to call you at noon tomorrow.';

class _ScriptedLlm extends LLMService {
  final List<String> promisePrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (params.systemPrompt != null) {
      yield _novellaWithPromise;
      return;
    }
    // The promise pass — no other prompt opens with these words.
    if (p.contains('You track PROMISES and commitments')) {
      promisePrompts.add(p);
      yield 'NONE';
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
      // Realism OFF on purpose: the Promise Ledger explicitly does not
      // require the engine (2026-08-08 decoupling), and a quiet turn keeps
      // this suite about exactly one prompt.
      'realism_default': false,
      // Ledger + journal are the pass's only gates; both default on, pinned
      // here so a default change fails loudly instead of skipping the test.
      'promise_ledger_enabled': true,
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
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('the promise prompt carries the clamped window, and the tail promise '
      'survives the clamp', () async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the promise-window test.',
      firstMessage: 'The porch light hums in the dusk.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-promise-1';
    await chat.setActiveCharacter(card);

    await chat.sendMessage('Will you call me tomorrow?');
    // The promise pass is fire-and-forget from the post-generation phase;
    // drain event-loop turns (no wall-clock settle) until it lands.
    for (var i = 0; i < 200 && llm.promisePrompts.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      llm.promisePrompts,
      hasLength(1),
      reason:
          'ledger + journal are on and the exchange contains "I promise" — '
          'the pass must fire exactly once for the reply',
    );
    final prompt = llm.promisePrompts.single;
    expect(
      prompt,
      contains(kEvalClampMarker),
      reason:
          'THE DIET. The old inline window shipped the full 21k-char '
          'novella — 38.3k chars of prompt for a 59-char verdict in the '
          'maintainer\'s own log.',
    );
    expect(
      prompt.length,
      lessThan(2 * kEvalMessageCharCap + 4000),
      reason: 'window ≈ one clamped reply + the short user turn + rubric',
    );
    expect(
      prompt,
      contains('I promise to call you at noon tomorrow'),
      reason:
          'the commitment sits at the reply\'s TAIL — a clamp that ate the '
          'tail would silently kill promise detection for verbose models',
    );
  });
}
