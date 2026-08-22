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

// RAG WIRING: day-stamped chronological injection + the per-turn receipt
// (2026-08-10 memory review). Drives the REAL ChatService with a scripted
// LLM and a fake MemoryService, on a context small enough that history
// genuinely drops — so what is proven is the god's retrieval phase itself:
// the block that reaches the model is stamped and in story order, the query
// carries photo markers, and the receipt lands in the generated message's
// metadata where the sidebar and web facade read it.
//
// Guards proven to fail before passing:
//   * remove chronologicalRagOrder from the block builder → the "cross-chat
//     line precedes the own-chat line" assertion goes red (relevance order
//     puts the own-chat line first here by construction)
//   * revert the query to displayText → the photo-marker query assertion
//     goes red (the marked message's displayText carries no marker)
//   * delete the stream-phase stamp → the receipt assertions go red
//
// REDESIGNED 2026-08-11 (flake kill, subject unchanged): the gate test used
// to DRIVE 21 real ChatService turns — ~190 scripted eval round-trips of
// pure ceremony — just to make the transcript outgrow the context. That
// wall-clock-heavy arrangement timed out at the default 30s on loaded CI
// runners twice (the suite's birth run 4da644b and run 31464121692), and
// the aborted turn's background churn then contaminated the sibling
// no-receipt test. Maintainer ruling: a flaky test is worse than no test.
// The precondition is now ARRANGED, not simulated — the oversized
// transcript is seeded straight into the DB (the session_load_regression
// pattern) and loaded, and exactly ONE real turn runs: the photo turn the
// assertions are actually about. Every assertion is byte-identical.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_ragwire_').path;
        }
        return null;
      });
}

/// Scripted backend that records every conversational prompt (the only call
/// carrying a system prompt) and answers the eval calls minimally.
class _ScriptedLlm extends LLMService {
  final List<String> chatPrompts = [];

  /// Long replies on purpose: the test needs the transcript to outgrow a
  /// 3072-token context so messages actually drop — while leaving the
  /// history budget comfortably positive, or the JOINT cap (correctly)
  /// drains every retrieved memory and the block never ships.
  static const _reply =
      '*She rocks slowly, the porch boards creaking under the runners, and '
      'talks about the garden, the neighbours, the way the light moves '
      'through the screen door in the late afternoon, unhurried. She lists '
      'the tomatoes that came in early, the fence post that needs setting, '
      'the dog two doors down that has learned to open the gate latch, the '
      'smell of cut grass drifting from the corner lot, and the way the '
      'cicadas start all at once as if someone threw a switch somewhere '
      'down the street, and she keeps talking, easy and unhurried, letting '
      'the evening stretch itself out as far as it will go.*';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (params.systemPrompt != null) {
      chatPrompts.add(p);
      yield _reply;
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture": "none"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

/// Fake retrieval: hands back one cross-chat memory and one memory from THIS
/// chat (an early position that carries realism_state), and records the
/// query. The own-chat memory deliberately outscores the cross-chat one, so
/// relevance order and story order DISAGREE — which is what lets the display
/// -order assertion actually mean something.
class _FakeMemory extends MemoryService {
  _FakeMemory(super.embedding, super.storage, super.db);

  String? lastQuery;

  @override
  Future<List<RetrievedMemory>> retrieve({
    required String queryText,
    required List<String> sourceCharacterIds,
    required String currentSessionId,
    int inContextStart = 0,
    int limit = 5,
    double minScore = MemoryService.kRagMinScore,
    Map<String, double>? characterPriorities,
    Set<String> sessionScopedCharacterIds = const {},
  }) async {
    lastQuery = queryText;
    return [
      RetrievedMemory(
        content: 'Nia: the porch swing creaked all night',
        characterId: 'c1',
        sessionId: currentSessionId,
        positionStart: 2,
        positionEnd: 2,
        score: 0.95,
      ),
      RetrievedMemory(
        content: 'You: remember the red kite on the pier',
        characterId: 'c1',
        sessionId: 'some-other-session',
        positionStart: 7,
        positionEnd: 7,
        score: 0.9,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;
  late _FakeMemory memory;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'rag_enabled': true,
      // Small enough that ~20 long turns overflow history and messages drop
      // (the retrieval gate), big enough that one short exchange does NOT
      // drop (the no-receipt test) and that the history budget stays
      // positive after the memory block (the joint cap would otherwise
      // correctly drain every memory — the first run of this suite proved
      // that at 1024).
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
    memory = _FakeMemory(EmbeddingService(storage), storage, db);
    chat.setMemoryService(memory);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  test(
    'retrieved lines reach the prompt day-stamped in story order, the query '
    'sees photo markers, and the receipt lands in message metadata',
    () async {
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the RAG wiring test.',
        firstMessage: 'The porch light hums in the dusk.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-ragwire-1';
      await chat.setActiveCharacter(card);

      // The precondition, ARRANGED rather than simulated: a transcript
      // already past the 3072-token budget, seeded straight into the DB and
      // loaded. 24 long messages ≈ 3.9k tokens of history, so assembly
      // drops the oldest and the retrieval gate opens on the very first
      // real turn below. Position 2 carries the realism_state stamp the
      // day-stamped own-chat line derives from.
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-ragwire',
          characterId: const Value('char-ragwire-1'),
        ),
      );
      for (var i = 0; i < 24; i++) {
        final isUser = i.isOdd;
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'seed-$i',
            sessionId: 'sess-ragwire',
            position: i,
            sender: isUser ? 'You' : 'Nia',
            isUser: isUser,
            swipes: Value('["${_ScriptedLlm._reply.replaceAll('*', '')}"]'),
            metadata: i == 2
                ? const Value('{"realism_state":{"dayCount":1}}')
                : const Value.absent(),
          ),
        );
      }
      await chat.loadSession('sess-ragwire');
      expect(chat.messages, hasLength(24), reason: 'the seed must load');

      // Mark an in-window user message as a photo turn: its promptText now
      // carries the marker, its displayText does not — which is exactly the
      // difference the query switch exists to carry.
      final photoMsg = chat.messages.lastWhere((m) => m.isUser);
      photoMsg.activeMetadata ??= {};
      photoMsg.activeMetadata!['is_user_image'] = true;
      photoMsg.activeMetadata!['image_caption'] = 'a red kite over the bay';

      await chat.sendMessage('That photo was from our last trip, remember what you said?');

      expect(
        memory.lastQuery,
        isNotNull,
        reason:
            'the retrieval gate never opened — the transcript did not '
            'outgrow the context, so nothing here was actually tested',
      );
      expect(
        memory.lastQuery,
        contains('[shared a photo: a red kite over the bay]'),
        reason:
            'THE QUERY SWITCH. displayText carries no photo marker, so a '
            'query built from it cannot retrieve what a photo-centered '
            'exchange is about.',
      );

      final prompt = llm.chatPrompts.last;
      expect(
        prompt,
        contains('from earlier'),
        reason:
            'gist-first frame — the old "Exact earlier lines … in story '
            'order" dump is no longer the normal (or quote-reach) header',
      );
      expect(prompt, isNot(contains('Exact earlier lines')));
      const otherLine = '- (another chat) You: remember the red kite';
      const ownLine = '- (Day 1) Nia: the porch swing creaked all night';
      expect(prompt, contains(otherLine));
      expect(
        prompt,
        contains(ownLine),
        reason:
            'the own-chat line must carry the story day its source message '
            'was written on (realism_state.dayCount at position 2)',
      );
      expect(
        prompt.indexOf(otherLine),
        lessThan(prompt.indexOf(ownLine)),
        reason:
            'DISPLAY ORDER. The own-chat memory outscores the cross-chat one '
            '(0.95 vs 0.9), so relevance order would render it first — '
            'story order puts the cross-chat line first. If this fails, the '
            'chronological reorder is gone and lines compete with the '
            'recap\'s timeline again.',
      );

      // The receipt: stamped on the generated reply, surfaced by the getter
      // the sidebar panel and web facade read.
      final receipt = chat.lastRagReceipt;
      expect(receipt, isNotNull);
      expect(receipt!['found'], 2);
      expect(receipt['journal_deduped'], 0);
      expect(receipt['budget_trimmed'], 0);
      final lines = receipt['injected'] as List;
      expect(lines, hasLength(2));
      expect((lines[0] as Map)['other_chat'], true);
      expect((lines[1] as Map)['day'], 1);
      expect((lines[1] as Map)['pos'], 2);
      // And it is message metadata, not transient state — the reply carries
      // it for the panel to find after any reload.
      final reply = chat.messages.lastWhere((m) => !m.isUser);
      expect(reply.activeMetadata?['rag_receipt'], isNotNull);
    },
  );

  test('a turn with nothing dropped stamps no receipt', () async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the RAG wiring test.',
      firstMessage: 'The porch light hums in the dusk.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-ragwire-2';
    await chat.setActiveCharacter(card);

    await chat.sendMessage('Evening. Mind if I sit?');

    expect(memory.lastQuery, isNull);
    expect(
      chat.lastRagReceipt,
      isNull,
      reason:
          'no retrieval ran, so the panel must say "no lookup needed" — a '
          'phantom receipt here would be the black box lying in the other '
          'direction',
    );
  });
}
