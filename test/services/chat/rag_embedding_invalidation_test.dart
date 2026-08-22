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

// TIMELINE INTEGRITY, RAG HALF (release audit 2026-08-15).
//
// Journal cards and Growth rings are both purged when a message is rewritten
// — regen, swipe, edit, delete — because both cite message POSITIONS, and a
// rewrite makes those citations describe events that no longer happened. The
// RAG message-window corpus cites exactly the same positions and had no
// invalidation whatsoever.
//
// Two consequences, both silent and permanent:
//   * the window's stored `content` is the PRE-rewrite text, and
//     MemoryService's dedupe is positional only (a range already present is
//     skipped forever), so the discarded reply was never re-embedded and got
//     injected 20+ turns later as a remembered-from-earlier line …
//     already happened". Delete did not delete.
//   * after a delete every later window's (start,end) addresses different
//     messages, mis-stamping story days and mis-aligning the journal de-dupe.
//
// These drive the REAL ChatService, so what is proven is the wiring — that the
// shared rewrite hook reaches the embedding corpus through the doors a user
// actually presses, not merely that a DELETE statement works.
//
// Proven to fail first: with the `_invalidateEmbeddingsFrom` call removed from
// `_invalidateJournalFrom`, both purge assertions below go red (the stale
// windows survive the rewrite).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
          return Directory.systemTemp.createTempSync('fpai_raginv_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She rocks the porch swing once.*';
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

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  /// Plant an embedded window exactly the way MemoryService would.
  Future<void> window(String sessionId, int start, int end, String text) =>
      db.insertEmbedding(
        MessageEmbeddingsCompanion(
          sessionId: Value(sessionId),
          positionStart: Value(start),
          positionEnd: Value(end),
          content: Value(text),
          embedding: Value(Uint8List.fromList(const [1, 2, 3, 4])),
          dimensions: const Value(4),
          characterId: const Value('char-raginv-1'),
        ),
      );

  Future<List<String>> corpus(String sessionId) async {
    final rows = await db.getEmbeddingsForCharacters(['char-raginv-1']);
    return [
      for (final r in rows)
        if (r.sessionId == sessionId) r.content,
    ]..sort();
  }

  Future<void> drainTurn() async {
    for (var i = 0; i < 400 && (chat.isGenerating || chat.isSettlingTurn); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Opens a chat and drives it to seven messages (greeting + three
  /// exchanges), so a rewrite can be aimed at a position later than the first
  /// stored window.
  Future<void> openSevenMessageChat() async {
    final card = CharacterCard(
      name: 'Mara',
      description: 'Exists only inside the RAG-invalidation test.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-raginv-1';
    await chat.setActiveCharacter(card);
    for (var i = 0; i < 3; i++) {
      await chat.sendMessage('Turn $i');
      await drainTurn();
    }
    expect(chat.messages, hasLength(7));
  }

  test('a delete purges the windows citing it — and only those', () async {
    await openSevenMessageChat();
    final sid = chat.currentSessionId!;
    await window(sid, 0, 4, 'the early exchange');
    await window(sid, 5, 9, 'the discarded reply about the car keys');
    // A different chat's corpus must never be touched by this chat's rewrite.
    await window('some-other-session', 0, 4, 'another chat entirely');

    chat.deleteMessage(5);
    await drainTurn();

    expect(
      await corpus(sid),
      ['the early exchange'],
      reason:
          'the (5,9) window holds the deleted text verbatim AND, after the '
          'shift, addresses different messages — nothing would ever re-embed '
          'it, because the dedupe is positional',
    );
    expect(
      await corpus('some-other-session'),
      ['another chat entirely'],
      reason: 'invalidation is session-scoped',
    );
  });

  test('an edit purges them too — same hook, same corpus', () async {
    await openSevenMessageChat();
    final sid = chat.currentSessionId!;
    await window(sid, 0, 4, 'the early exchange');
    await window(sid, 5, 9, 'the text as it read before the edit');

    chat.editMessage(6, 'She says something else entirely.');
    await drainTurn();

    expect(await corpus(sid), ['the early exchange']);
  });
}
