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

// The item-memory feed, wired layer (2026-08-11 maintainer design), two
// halves:
//
//  A. THE NO-RAG FLOOR IS REAL: a cold item card resurfaces through the
//     real JournalStore + JournalInjection with NO embedder anywhere,
//     purely because the turn named the item — and the retrieval re-warms
//     it exactly like the cosine path would.
//
//  B. THE FEED IS WIRED: the REAL ChatService, driven by a scripted LLM
//     reporting inventory ops, writes the diary card with the canonical
//     name, the story stamp and the reply receipt — and a later placement
//     of the same item RETIRES the old card, so "where are my keys" always
//     has exactly one answer.
//
// Guards proven to fail before passing: disabling the lexical block in
// journal_injection sends A red; the one-live-card dedup assert in B goes
// red if the retire loop is removed.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show
        JournalPhysics,
        JournalStore,
        PocketSection,
        kEvalClampMarker,
        kEvalMessageCharCap;
import 'package:front_porch_ai/services/chat/prompt_injection/journal_injection.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_itemmem_').path;
        }
        return null;
      });
}

/// Replies with a fixed inventory op whenever the pockets eval asks, and a
/// plain scene line for the main generation. Reasoning: with Realism off and
/// Afterglow idle only ONE bookkeeping feature is live, so fusion never
/// fires and the standalone pockets eval is the single structured question
/// in flight — no other prompt contains the wardrobe lead-in.
class _ScriptedLlm extends LLMService {
  String inventoryJson = '{"inventory_ops": []}';
  String reply = '*She hums on the porch, unhurried.*';
  final List<String> pocketsPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield reply;
      return;
    }
    if (params.prompt.contains('You are keeping track of what')) {
      pocketsPrompts.add(params.prompt);
      yield inventoryJson;
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

  group('A. the keyword floor through the real store + injection', () {
    late AppDatabase db;
    late JournalStore store;

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db); // NO embedder — the floor
    });

    tearDown(() => db.close());

    JournalInjection injection() => JournalInjection(
      store: store,
      getSessionId: () => 's1',
      getCurrentEmotion: () => '',
      getCurrentStoryDay: () => 3,
      getStoryStartDate: () => DateTime(2026, 6, 1),
    );

    Future<void> insertColdKeysCard() => db.insertJournalCard(
      JournalMemoriesCompanion(
        sessionId: const Value('s1'),
        characterId: const Value('mara'),
        content: const Value('I set my car keys down — on the hallway table.'),
        category: const Value('item'),
        heat: const Value(0.1), // well below the cold threshold
        metadata: const Value('{"kind":"item","item":"car keys"}'),
      ),
    );

    test('naming the item resurfaces and re-warms its cold card', () async {
      await insertColdKeysCard();
      final block = await injection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'You',
        queryText: 'You: where did I put my keys?',
      );
      expect(
        block.text,
        contains('hallway table'),
        reason: 'cold card, no embedder — only the keyword floor can do this',
      );
      expect(block.text, contains('belongings'));
      final card = (await db.getJournalCards('s1', 'mara')).single;
      expect(card.heat, JournalPhysics.kRewarmHeat);
      expect(card.accessCount, 1, reason: 'retrieval must record the access');
    });

    test('an unrelated turn leaves the cold card cold', () async {
      await insertColdKeysCard();
      final block = await injection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'You',
        queryText: 'You: lovely weather on the porch tonight',
      );
      expect(block.text, isEmpty);
      expect((await db.getJournalCards('s1', 'mara')).single.heat, 0.1);
    });
  });

  group('B. the feed end to end through the real ChatService', () {
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

    Future<List<JournalMemoryData>> itemCards() async {
      final cards = await db.getJournalCardsForSession(chat.currentSessionId!);
      return [
        for (final c in cards)
          if (JournalPhysics.isItemCard(c)) c,
      ];
    }

    Future<void> drainUntil(Future<bool> Function() done) async {
      for (var i = 0; i < 300 && !await done(); i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a setdown becomes ONE canonical diary card, and a later placement '
        'of the same item replaces it', () async {
      final card = CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the item-memory test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
          inventory: {
            'carrying': ['car keys'],
          },
        ),
      )..dbId = 'char-itemmem-1';
      await chat.setActiveCharacter(card);

      llm.inventoryJson =
          '{"inventory_ops": [{"op": "setdown", "item": "the keys", '
          '"where": "on the hallway table"}]}';
      await chat.sendMessage('Make yourself at home.');
      await drainUntil(() async => (await itemCards()).isNotEmpty);

      var cards = await itemCards();
      expect(cards, hasLength(1));
      expect(
        cards.single.content,
        'I set my car keys down — on the hallway table.',
        reason:
            'canonical record name ("car keys"), not the model\'s "the keys"',
      );
      expect(JournalPhysics.itemOf(cards.single), 'car keys');
      expect(
        JournalStore.stampOf(cards.single).$1,
        isNotNull,
        reason: 'item cards are story-stamped like every Living Time card',
      );
      expect(
        cards.single.sourceMessageIds,
        isNotNull,
        reason: 'the reply receipt enrolls the card in timeline invalidation',
      );

      // She takes them back and puts them somewhere new — the old placement
      // memory must be REPLACED, not accumulated.
      llm.inventoryJson =
          '{"inventory_ops": [{"op": "pickup", "item": "keys"}, '
          '{"op": "setdown", "item": "keys", "where": "by the porch rail"}]}';
      await chat.sendMessage('Heading out soon?');
      await drainUntil(() async {
        final c = await itemCards();
        return c.length == 1 && c.single.content.contains('porch rail');
      });

      cards = await itemCards();
      expect(
        cards,
        hasLength(1),
        reason: '"where are my keys" must have exactly one diary answer',
      );
      expect(
        cards.single.content,
        'I set my car keys down — by the porch rail.',
      );
    });

    test('the eraser retires the live item-memory card for that name', () async {
      // Diary lag residual: removePocketItem rewrote the kit but left the
      // "I set my keys down…" card live, so "where are my keys?" still lied.
      final card = CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the item-memory test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
          inventory: {
            'carrying': ['car keys'],
          },
        ),
      )..dbId = 'char-itemmem-eraser';
      await chat.setActiveCharacter(card);

      llm.inventoryJson =
          '{"inventory_ops": [{"op": "setdown", "item": "the keys", '
          '"where": "on the hallway table"}]}';
      await chat.sendMessage('Make yourself at home.');
      await drainUntil(() async => (await itemCards()).isNotEmpty);
      expect(await itemCards(), hasLength(1));

      // Same id the desktop/web eraser passes (stableGroupId), not dbId.
      final ownerId = chat.characterIdFor(card);
      final pockets = chat.pocketsFor(ownerId);
      expect(pockets, isNotNull);
      // After setdown the keys live in set-aside, not carrying.
      final setAside = pockets!.setAside;
      expect(setAside, isNotEmpty);
      final idx = setAside.indexWhere(
        (e) => e.item.name.toLowerCase().contains('key'),
      );
      expect(idx, greaterThanOrEqualTo(0));

      await chat.removePocketItem(
        ownerId,
        section: PocketSection.setAside,
        index: idx,
      );
      await drainUntil(() async => (await itemCards()).isEmpty);

      expect(
        await itemCards(),
        isEmpty,
        reason:
            'eraser is the human override — diary must not keep the placement',
      );
    });

    test('a novella reply reaches the bookkeeping prompt clamped', () async {
      // The eval diet clamped every judge window but missed the bookkeeping
      // carriers — a 20k-char reply rode the pockets prompt RAW (hostile
      // review, 2026-08-11).
      final card = CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the item-memory test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
          inventory: {
            'carrying': ['car keys'],
          },
        ),
      )..dbId = 'char-itemmem-2';
      await chat.setActiveCharacter(card);

      llm.reply =
          '*She talks and talks.* '
          '${'The porch boards creak under the runners, unhurried. ' * 400}'
          'Then she sets her keys on the sill.';
      await chat.sendMessage('Long evening?');
      await drainUntil(() async => llm.pocketsPrompts.isNotEmpty);

      final prompt = llm.pocketsPrompts.single;
      expect(prompt, contains(kEvalClampMarker));
      expect(
        prompt.length,
        lessThan(2 * kEvalMessageCharCap + 4000),
        reason:
            'clamped reply + clamped exchange slice + rubric — never the '
            'raw novella. (The first draft of this bound sat above the '
            'unclamped size and proved nothing — negative-checked.)',
      );
      expect(
        prompt,
        contains('sets her keys on the sill'),
        reason: 'the tail survives the clamp — that is where changes land',
      );
    });
  });
}
