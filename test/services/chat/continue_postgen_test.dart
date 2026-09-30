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

// CONTINUE MUST NOT BE INVISIBLE TO THE POST-GENERATION BOOKKEEPING
// (maintainer report, 2026-08-12: "I'm guessing they do not update to match
// the extra generation from the continue button being pressed by the user").
//
// The guess was right, and it was a PERMANENT blind spot, not a delay: the
// needs-impact, climax, pockets and posture passes were all skipped on
// Continue, and each of them only ever reads the newest reply — so "she
// sets the keys on the table" arriving via Continue never reached any
// bookkeeping, ever. The fix scores the NEW text only, as an incremental
// extension of the exchange: a double-apply of the first half is impossible
// by construction, decay is untouched (no new turn), and the message's
// pockets_before stamp keeps the turn's TRUE pre-state so regen and
// tail-delete still rewind to the base, not to the middle of the turn.
//
// Guards proven to fail before passing:
//  * tests 1 and 3 go red with the old skip restored (score '' on Continue);
//  * test 2's stamp assert goes red with the preserve branch disabled
//    (continuation overwrites pockets_before with the mid-turn record).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_contpg_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String replyText = '*She hums on the porch, unhurried.*';
  String inventoryJson = '{"inventory_ops": []}';
  String needsJson = '{"hunger_delta": 0, "reason": "none"}';
  int pocketsPrompts = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield replyText;
      return;
    }
    final p = params.prompt;
    // Pockets bookkeeping (standalone AND the fused reply-facts carrier —
    // both prompts contain this header; posture parses nothing from the
    // inventory JSON and skips, exactly like a failed standalone pass).
    if (p.contains('You are keeping track of what')) {
      pocketsPrompts++;
      yield inventoryJson;
      return;
    }
    if (p.contains('hunger_delta')) {
      yield needsJson;
      return;
    }
    // Realism evals — inert zeros (same script as pockets_rewind H3).
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
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture":"none"}';
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
      'realism_default': false,
      'pockets_enabled': true,
      'journal_enabled': false,
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

  CharacterCard card(String dbId, {bool engine = false}) => CharacterCard(
    name: 'Mara',
    description: 'Exists only inside the continue-postgen test.',
    firstMessage: 'The porch light hums.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: engine,
      needsSimEnabled: engine,
      chaosModeEnabled: false,
      inventory: {
        'carrying': ['car keys'],
      },
    ),
  )..dbId = dbId;

  Pockets record() =>
      chat.pocketsFor(chat.characterIdFor(chat.activeCharacter!))!;

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 300 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    // A few extra microtasks for the fire-and-forget tails.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('an op arriving via Continue reaches the record — and tail delete '
      'still rewinds to the turn base', () async {
    await chat.setActiveCharacter(card('char-cont-1'));

    // First half: no ops. Keys stay in hand.
    await chat.sendMessage('Make yourself at home.');
    await drainTurn();
    expect(record().carrying.single.name, 'car keys');

    // The Continue: she finally sets them down — only the NEW text says so.
    llm.replyText = ' She sets her keys down on the hallway table.';
    llm.inventoryJson =
        '{"inventory_ops": [{"op": "setdown", "item": "keys", '
        '"where": "on the hallway table"}]}';
    await chat.continueGeneration();
    await drainTurn();

    expect(
      record().setAside.map((e) => e.item.name),
      contains('car keys'),
      reason:
          'the user paid a Continue for this exact event — the pockets pass '
          'must read the new text (pre-fix it was skipped and the keys '
          'stayed in hand forever)',
    );
    expect(record().carrying, isEmpty);

    // The stamp still holds the TURN base (keys in hand), so deleting the
    // reply un-happens the whole turn, continuation included.
    chat.deleteMessage(chat.messages.length - 1);
    expect(record().carrying.single.name, 'car keys');
    expect(record().setAside, isEmpty);
  });

  test(
    'a continuation preserves the first half\'s pockets_before stamp',
    () async {
      await chat.setActiveCharacter(card('char-cont-2'));

      // First half parks the keys — pockets_before = keys in hand.
      llm.inventoryJson =
          '{"inventory_ops": [{"op": "setdown", "item": "keys", '
          '"where": "on the hallway table"}]}';
      await chat.sendMessage('Make yourself at home.');
      await drainTurn();
      expect(record().setAside.single.item.name, 'car keys');

      // Continuation picks them back up. Ops apply incrementally…
      llm.replyText = ' On second thought she scoops the keys back up.';
      llm.inventoryJson =
          '{"inventory_ops": [{"op": "pickup", "item": "keys"}]}';
      await chat.continueGeneration();
      await drainTurn();
      expect(record().carrying.single.name, 'car keys');
      expect(record().setAside, isEmpty);

      // …but the before-stamp must still be the TURN's pre-state (keys in
      // hand), not the mid-turn record the continuation started from. A
      // regen that replays with no ops must land on the base.
      final stamp = chat.messages.last.metadata?['pockets_before'] as Map?;
      final stampRecord = Pockets.fromJson(stamp?['record']);
      expect(
        stampRecord.carrying.map((e) => e.name),
        contains('car keys'),
        reason:
            'overwriting pockets_before mid-turn would make regen and tail '
            'delete rewind to the middle of the turn instead of its start',
      );
      expect(stampRecord.setAside, isEmpty);

      llm.replyText = '*She hums, hands empty of intent.*';
      llm.inventoryJson = '{"inventory_ops": []}';
      await chat.regenerateLastMessage();
      await drainTurn();
      expect(record().carrying.single.name, 'car keys');
      expect(record().setAside, isEmpty);
    },
  );

  test(
    'needs impact arriving via Continue applies once and merges the chip',
    () async {
      await chat.setActiveCharacter(card('char-cont-3', engine: true));
      await chat.setRealismEnabled(true);

      llm.needsJson = '{"hunger_delta": -5, "reason": "long porch talk"}';
      await chat.sendMessage('Tell me about your day.');
      await drainTurn();
      final hungerAfterTurn = chat.needsSimulation.vector['hunger']!;
      final chipAfterTurn =
          ((chat.messages.last.activeMetadata?['needs_deltas']
                      as Map?)?['hunger']
                  as Map?)?['delta']
              as num?;
      expect(
        chipAfterTurn,
        isNotNull,
        reason: 'the original turn must attach a hunger chip to build on',
      );

      // Continue: she finishes nothing and gets hungrier — only the new text
      // is scored, so exactly -7 lands (no decay tick, no -5 re-apply).
      llm.replyText = ' Her stomach growls through the last of the story.';
      llm.needsJson = '{"hunger_delta": -7, "reason": "still no dinner"}';
      await chat.continueGeneration();
      await drainTurn();

      expect(
        chat.needsSimulation.vector['hunger'],
        hungerAfterTurn - 7,
        reason:
            'the continuation\'s impact must land exactly once — unchanged '
            'means the pass was skipped (the old bug), more than -7 means the '
            'first half was re-applied (the double-apply the old skip feared)',
      );
      final chipAfterContinue =
          ((chat.messages.last.activeMetadata?['needs_deltas']
                      as Map?)?['hunger']
                  as Map?)?['delta']
              as num?;
      expect(
        chipAfterContinue,
        chipAfterTurn! - 7,
        reason:
            'the chip is live-vector minus the pre-turn stamp, so it must now '
            'read as the merged whole-turn delta',
      );
    },
  );

  test(
    'continuing a Scene Guest\'s tail scores nothing against the host',
    () async {
      // The speaker resolution for Continue falls back to the HOST in 1:1, so
      // without the guest guard the guest's continuation text would run the
      // pockets/needs/climax family against the host's record. Seeded
      // directly (arrange-don't-simulate): a guest-authored tail is any
      // non-user 1:1 message whose characterId differs from the host's.
      await chat.setActiveCharacter(card('char-cont-4'));
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-guest-cont',
          characterId: const Value('char-cont-4'),
        ),
      );
      for (final (i, seed) in const [
        ('Mara', false, 'char-cont-4'),
        ('You', true, null),
        ('Riley', false, 'guest-riley'),
      ].indexed) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'guest-seed-$i',
            sessionId: 'sess-guest-cont',
            position: i,
            sender: seed.$1,
            isUser: seed.$2,
            characterId: Value(seed.$3),
            swipes: const Value('["*The porch light hums while they talk.*"]'),
          ),
        );
      }
      await chat.loadSession('sess-guest-cont');
      expect(chat.messages, hasLength(3));
      expect(record().carrying.single.name, 'car keys');

      llm.pocketsPrompts = 0;
      llm.replyText = ' Riley keeps talking about setting keys down.';
      llm.inventoryJson =
          '{"inventory_ops": [{"op": "setdown", "item": "keys", '
          '"where": "on the hallway table"}]}';
      await chat.continueGeneration();
      await drainTurn();

      expect(
        record().carrying.single.name,
        'car keys',
        reason:
            'the guest\'s words must not move the HOST\'s belongings — the '
            'incremental pass skips guest-authored tails entirely',
      );
      expect(record().setAside, isEmpty);
      expect(
        llm.pocketsPrompts,
        0,
        reason: 'no bookkeeping call should even fire for a guest tail',
      );
    },
  );
}
