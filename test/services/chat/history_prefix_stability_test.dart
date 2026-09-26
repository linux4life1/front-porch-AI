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

// PREFIX STABILITY ON OVERFLOWING CHATS (maintainer report, 2026-08-11:
// oMLX at 2.8% cache efficiency, ~52k tokens re-prefilled EVERY turn).
//
// Prefix caches reuse the longest byte-identical HEAD of consecutive
// prompts. The app's whole prompt order exists for this (every changing
// block rides post-history) — but on an over-budget chat the history
// window is re-fitted from scratch each turn, and when the post-history
// blocks wobble the budget (author's note edits, journal re-sorts,
// expand-memory quotes), a drop point near a chunk boundary OSCILLATES
// across it. Every flip moves the transcript's first byte and the entire
// prefill is paid again. The monotonic anchor in chat_service_history.dart
// pins the window start per session: once dropped, stays dropped.
//
// This suite drives the REAL ChatService on a DB-seeded over-budget chat
// and asserts the invariant the cache actually depends on: consecutive
// chat prompts share a byte-identical prefix covering (at least) the whole
// transcript region — INCLUDING across a turn whose fixed blocks changed
// size in both directions.
//
// Guard proven to fail before passing: with the anchor neutered (effective
// drop = raw drop, i.e. the pre-fix behavior), the wobble turn's shared
// prefix collapses to the static head and the assertion goes red.

import 'dart:io';
import 'dart:math';

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
          return Directory.systemTemp.createTempSync('fpai_prefix_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  final List<String> chatPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatPrompts.add(params.prompt);
      yield '*She rocks slowly and hums about the porch, the garden, and '
          'the way the evening light moves through the screen door.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

int _commonPrefix(String a, String b) {
  final n = min(a.length, b.length);
  var i = 0;
  while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
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
      // Small on purpose: the seeded transcript must overflow so the
      // window-fitting path actually runs — an under-budget chat never
      // drops and is trivially prefix-stable.
      'context_size': 3072,
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

  test('consecutive prompts keep the transcript prefix — even when the '
      'fixed blocks wobble in both directions', () async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the prefix-stability test.',
      firstMessage: 'The porch light hums in the dusk.',
    )..dbId = 'char-prefix-1';
    await chat.setActiveCharacter(card);

    // An over-budget transcript, seeded directly (the arrange-don't-
    // simulate rule): 30 long messages ≈ well past the 3072-token budget.
    const filler =
        'The porch boards creak under the runners as the light moves '
        'through the screen door, unhurried and warm, while the cicadas '
        'start all at once as if someone threw a switch down the street. ';
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-prefix',
        characterId: const Value('char-prefix-1'),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'seed-$i',
          sessionId: 'sess-prefix',
          position: i,
          sender: i.isOdd ? 'You' : 'Nia',
          isUser: i.isOdd,
          swipes: Value('["${filler * 3}(turn $i)"]'),
        ),
      );
    }
    await chat.loadSession('sess-prefix');
    // Pin the baseline reserve so the wobble below is deterministic in both
    // directions regardless of storage defaults.
    chat.sessionGenSettings = ChatGenerationSettings()..maxLength = 400;

    await chat.sendMessage('Tell me about the evening.');
    // WOBBLE the history budget between turns, both directions, through the
    // generation reserve (maxLength rides fixed accounting but adds no
    // prompt text — the clean isolation of the budget effect; an author's
    // note would ALSO splice text into the transcript by design and drown
    // the signal). Pre-anchor, a downswing+restore like this flipped the
    // drop point across a chunk boundary and re-prefilled ~52k tokens per
    // turn on the maintainer's oMLX dashboard.
    chat.sessionGenSettings = ChatGenerationSettings()..maxLength = 1000;
    await chat.sendMessage('And the garden?');
    chat.sessionGenSettings = ChatGenerationSettings()..maxLength = 400;
    await chat.sendMessage('And the neighbours?');
    // …and one ordinary turn with nothing changing at all.
    await chat.sendMessage('Stay a while longer?');

    expect(llm.chatPrompts, hasLength(4));
    // Pair 1→2 is deliberately NOT asserted: the budget genuinely shrank,
    // so advancing the window (and paying one re-prefill) is CORRECT — the
    // anchor's promise is everything after: the restore leg must not move
    // the window back (pair 2→3), and steady state must extend it
    // byte-for-byte (pair 3→4).
    for (var i = 2; i < llm.chatPrompts.length; i++) {
      final prev = llm.chatPrompts[i - 1];
      final next = llm.chatPrompts[i];
      final shared = _commonPrefix(prev, next);
      // The transcript region must survive whole: the shared prefix ends
      // inside the post-history tail, so it covers well over half of the
      // previous prompt. When the window start moves, the shared prefix
      // collapses to the static head (a small fraction) — the failure the
      // anchor exists to prevent.
      expect(
        shared,
        greaterThan(prev.length * 6 ~/ 10),
        reason:
            'turn ${i + 1}\'s prompt must extend turn $i\'s transcript, '
            'not rewrite it (shared $shared of ${prev.length} chars) — '
            'a collapsed prefix is the 2.8%-cache-efficiency bug',
      );
    }
  });
}
