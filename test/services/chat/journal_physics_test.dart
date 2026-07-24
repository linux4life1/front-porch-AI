// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for The Journal phase 2 — emotional physics
// (docs/design/journal-memory.md §4.4):
// - journal_physics.dart — flashbulb decay, hot/cold threshold, emotion
//   families, mood congruence, salient-event detection (pure functions)
// - journal_store.dart physics — per-pass cooling, re-warm on retrieval,
//   trim-by-coldest, revision re-warm + embedding invalidation, embedMissing
// - journal_injection.dart — hot-set ordering with mood boost, cold cards
//   excluded from the always-injected set, semantic resurfacing + re-warm.

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/journal_injection.dart';

ChatMessage _msg(String sender, String text, {Map<String, dynamic>? metadata}) =>
    ChatMessage(text: text, sender: sender, isUser: false, metadata: metadata);

Uint8List _vecBytes(List<double> v) {
  final floats = Float32List.fromList(v.map((e) => e.toDouble()).toList());
  return Uint8List.view(floats.buffer);
}

void main() {
  group('JournalPhysics pure functions', () {
    JournalMemoryData card({
      double heat = 1.0,
      String? intensity,
      String? emotion,
      bool pinned = false,
      String? kind,
    }) => JournalMemoryData(
      id: 'x',
      sessionId: 's1',
      characterId: 'mara',
      content: 'c',
      category: 'moment',
      emotionLabel: emotion,
      emotionIntensity: intensity,
      heat: heat,
      accessCount: 0,
      pinned: pinned,
      dimensions: 0,
      metadata: kind == null ? null : '{"kind":"$kind"}',
      createdAt: DateTime(2026),
      lastAccessedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('flashbulb decay: mild fades normally, strong barely at all', () {
      expect(JournalPhysics.cooledHeat(card(intensity: 'mild')), closeTo(0.85, 1e-9));
      expect(JournalPhysics.cooledHeat(card(intensity: null)), closeTo(0.85, 1e-9));
      expect(JournalPhysics.cooledHeat(card(intensity: 'moderate')), closeTo(0.925, 1e-9));
      expect(JournalPhysics.cooledHeat(card(intensity: 'strong')), closeTo(0.9775, 1e-9));
    });

    test('pinned never decays and heat floors at zero', () {
      expect(JournalPhysics.cooledHeat(card(pinned: true)), 1.0);
      expect(JournalPhysics.cooledHeat(card(heat: 0.05)), 0.0);
    });

    test('milestone cards never cool but are not always-injected (Living Time v1.5)', () {
      final m = card(kind: 'milestone', heat: 1.0, intensity: 'mild');
      expect(JournalPhysics.isMilestone(m), isTrue);
      expect(JournalPhysics.cooledHeat(m), 1.0);
      expect(JournalPhysics.isHot(m), isFalse);
      expect(JournalPhysics.cardKind(m), 'milestone');
    });

    test('promise cards are ledger-class (Train B)', () {
      final p = card(kind: 'promise', heat: 1.0, intensity: 'mild');
      expect(JournalPhysics.isPromise(p), isTrue);
      expect(JournalPhysics.isLedgerCard(p), isTrue);
      expect(JournalPhysics.cooledHeat(p), 1.0);
      expect(JournalPhysics.isHot(p), isFalse);
    });

    test('hot/cold threshold, pinned always hot', () {
      expect(JournalPhysics.isHot(card(heat: JournalPhysics.kColdThreshold)), isTrue);
      expect(JournalPhysics.isHot(card(heat: 0.1)), isFalse);
      expect(JournalPhysics.isHot(card(heat: 0.0, pinned: true)), isTrue);
    });

    test('emotion families map nuanced labels via nuancedToStandard', () {
      expect(JournalPhysics.emotionFamily('wistful'), 'sadness');
      expect(JournalPhysics.emotionFamily('Melancholy '), 'sadness');
      expect(JournalPhysics.emotionFamily('taken aback'), 'surprise');
      expect(JournalPhysics.emotionFamily('gribble'), 'gribble'); // unknown = own family
      expect(JournalPhysics.emotionFamily(null), '');
    });

    test('mood congruence matches by family, never on empty current', () {
      expect(JournalPhysics.moodCongruent('wistful', 'melancholy'), isTrue);
      expect(JournalPhysics.moodCongruent('joyful', 'melancholy'), isFalse);
      expect(JournalPhysics.moodCongruent('sad', ''), isFalse);
      expect(JournalPhysics.moodCongruent(null, 'sad'), isFalse);
    });

    test('hot sort key adds the mood boost only when congruent', () {
      final sad = card(heat: 0.9, emotion: 'melancholy');
      expect(JournalPhysics.hotSortKey(sad, 'wistful'), closeTo(1.15, 1e-9));
      expect(JournalPhysics.hotSortKey(sad, 'joyful'), closeTo(0.9, 1e-9));
    });

    test('salient events: big swings, trust repair, chance time', () {
      expect(
        JournalPhysics.hasSalientEvent([
          _msg('Mara', 'x', metadata: {'bond_delta': JournalPhysics.kEventBondSwing}),
        ]),
        isTrue,
      );
      expect(
        JournalPhysics.hasSalientEvent([
          _msg('Mara', 'x', metadata: {'bond_delta': -JournalPhysics.kEventBondSwing}),
        ]),
        isTrue,
      );
      expect(
        JournalPhysics.hasSalientEvent([
          _msg('Mara', 'x', metadata: {'bond_delta': 3, 'trust_delta': -4}),
        ]),
        isFalse,
      );
      expect(
        JournalPhysics.hasSalientEvent([
          _msg('Mara', 'x', metadata: {'trust_repair_verdict': 'forgiven'}),
        ]),
        isTrue,
      );
      expect(
        JournalPhysics.hasSalientEvent([
          _msg('Mara', 'x', metadata: {'chance_time_event': 'A stranger arrives'}),
        ]),
        isTrue,
      );
      expect(JournalPhysics.hasSalientEvent([_msg('Mara', 'plain')]), isFalse);
    });
  });

  group('JournalStore emotional physics', () {
    late AppDatabase db;
    late JournalStore store;

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<JournalMemoryData> addOne(
      String content, {
      String? intensity,
      String? emotion,
    }) async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: content,
        category: 'moment',
        emotionLabel: emotion,
        emotionIntensity: intensity,
        maxCards: 200,
      );
      return (await store.cardsFor('s1', 'mara'))
          .firstWhere((c) => c.content == content);
    }

    test('coolCards applies intensity-modified decay, skips pinned', () async {
      await addOne('mild one', intensity: 'mild');
      await addOne('strong one', intensity: 'strong');
      final pinnedCard = await addOne('pinned one');
      await store.setPinned(pinnedCard.id, true);

      await store.coolCards('s1', 'mara');

      final byContent = {
        for (final c in await store.cardsFor('s1', 'mara')) c.content: c,
      };
      expect(byContent['mild one']!.heat, closeTo(0.85, 1e-6));
      expect(byContent['strong one']!.heat, closeTo(0.9775, 1e-6));
      expect(byContent['pinned one']!.heat, 1.0);
    });

    test('cap trims the coldest unpinned card, not the oldest', () async {
      final oldCold = await addOne('old but cold');
      final newer = await addOne('newer and warm');
      // Make the NEWER card the cold one — the trim must chase heat, not age.
      await db.updateJournalCard(
        newer.id,
        const JournalMemoriesCompanion(heat: Value(0.1)),
      );
      await db.updateJournalCard(
        oldCold.id,
        const JournalMemoriesCompanion(heat: Value(0.9)),
      );
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'the straw',
        category: 'moment',
        maxCards: 2,
      );
      expect(
        (await store.cardsFor('s1', 'mara')).map((c) => c.content).toSet(),
        {'old but cold', 'the straw'},
      );
    });

    test('rewarmCard restores heat and records the access', () async {
      final card = await addOne('once forgotten');
      await db.updateJournalCard(
        card.id,
        const JournalMemoriesCompanion(heat: Value(0.1)),
      );
      final cold = (await store.cardsFor('s1', 'mara')).single;
      await store.rewarmCard(cold);
      final warmed = (await store.cardsFor('s1', 'mara')).single;
      expect(warmed.heat, JournalPhysics.kRewarmHeat);
      expect(warmed.accessCount, 1);
      expect(
        warmed.lastAccessedAt.isAfter(cold.lastAccessedAt) ||
            warmed.lastAccessedAt.isAtSameMomentAs(cold.lastAccessedAt),
        isTrue,
      );

      // Re-warming never COOLS a card that is already hotter.
      await db.updateJournalCard(
        card.id,
        const JournalMemoriesCompanion(heat: Value(0.9)),
      );
      await store.rewarmCard((await store.cardsFor('s1', 'mara')).single);
      expect((await store.cardsFor('s1', 'mara')).single.heat, 0.9);
    });

    test('revision re-warms the card and drops a stale embedding', () async {
      final card = await addOne('original text');
      await db.updateJournalCard(
        card.id,
        JournalMemoriesCompanion(
          heat: const Value(0.2),
          embedding: Value(_vecBytes([1, 0])),
          dimensions: const Value(2),
        ),
      );
      final cold = (await store.cardsFor('s1', 'mara')).single;
      await store.reviseCard(cold, content: 'revised text');
      final revised = (await store.cardsFor('s1', 'mara')).single;
      expect(revised.heat, JournalPhysics.kMaxHeat);
      expect(revised.embedding, isNull); // stale vector invalidated
      expect(revised.dimensions, 0);

      // A feeling-only revision keeps the (still valid) text embedding.
      await db.updateJournalCard(
        revised.id,
        JournalMemoriesCompanion(
          embedding: Value(_vecBytes([1, 0])),
          dimensions: const Value(2),
        ),
      );
      await store.reviseCard(
        (await store.cardsFor('s1', 'mara')).single,
        feeling: 'proud',
      );
      expect((await store.cardsFor('s1', 'mara')).single.embedding, isNotNull);
    });

    test('embedMissing vectors only unembedded cards; no embedder = no-op',
        () async {
      var calls = 0;
      final embeddingStore = JournalStore(
        getDb: () => db,
        embedText: (text) async {
          calls++;
          return [0.5, 0.5, 0.5];
        },
      );
      await embeddingStore.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: 'needs a vector',
        category: 'moment',
        maxCards: 200,
      );
      await store.embedMissing('s1', 'mara'); // store has NO embedder
      expect(calls, 0);
      expect(
        (await store.cardsFor('s1', 'mara')).single.embedding,
        isNull,
      );

      await embeddingStore.embedMissing('s1', 'mara');
      expect(calls, 1);
      final card = (await store.cardsFor('s1', 'mara')).single;
      expect(card.embedding, isNotNull);
      expect(card.dimensions, 3);

      // Already-embedded cards are skipped on the next sweep.
      await embeddingStore.embedMissing('s1', 'mara');
      expect(calls, 1);
    });
  });

  group('JournalInjection with physics', () {
    late AppDatabase db;
    late JournalStore store;
    String currentEmotion = '';

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db, embedText: (t) async => [1.0, 0.0]);
      currentEmotion = '';
    });

    tearDown(() async {
      await db.close();
    });

    JournalInjection buildInjection() => JournalInjection(
      store: store,
      getSessionId: () => 's1',
      getCurrentEmotion: () => currentEmotion,
      getCurrentStoryDay: () => 1,
      getStoryStartDate: () => DateTime.utc(2026, 6, 30),
    );

    Future<JournalMemoryData> addOne(String content, {String? emotion}) async {
      await store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: content,
        category: 'moment',
        emotionLabel: emotion,
        maxCards: 200,
      );
      return (await store.cardsFor('s1', 'mara'))
          .firstWhere((c) => c.content == content);
    }

    test('cold cards leave the always-injected set; pinned cold stay', () async {
      final cold = await addOne('gone cold');
      await db.updateJournalCard(
        cold.id,
        const JournalMemoriesCompanion(heat: Value(0.1)),
      );
      final pinnedCold = await addOne('pinned survivor');
      await db.updateJournalCard(
        pinnedCold.id,
        const JournalMemoriesCompanion(heat: Value(0.0), pinned: Value(true)),
      );

      final block = (await buildInjection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Sam',
      )).text;
      expect(block, isNot(contains('gone cold')));
      expect(block, contains('pinned survivor'));
    });

    test('mood congruence lifts a cooler matching memory up the order',
        () async {
      final sadOlder = await addOne('the sad one', emotion: 'melancholy');
      await db.updateJournalCard(
        sadOlder.id,
        const JournalMemoriesCompanion(heat: Value(0.9)),
      );
      await addOne('the joyful one', emotion: 'joyful'); // newer, heat 1.0

      currentEmotion = 'wistful'; // sadness family → boost the sad card
      final block = (await buildInjection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Sam',
      )).text;
      expect(
        block.indexOf('the sad one'),
        lessThan(block.indexOf('the joyful one')),
      );

      currentEmotion = 'neutral'; // no boost → plain heat order wins
      final unboosted = (await buildInjection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Sam',
      )).text;
      expect(
        unboosted.indexOf('the joyful one'),
        lessThan(unboosted.indexOf('the sad one')),
      );
    });

    test('semantic retrieval resurfaces and re-warms a cold card', () async {
      final cold = await addOne('the lighthouse trip');
      await db.updateJournalCard(
        cold.id,
        JournalMemoriesCompanion(
          heat: const Value(0.1),
          embedding: Value(_vecBytes([1, 0])), // aligned with the fake query
          dimensions: const Value(2),
        ),
      );
      await addOne('still warm'); // keeps the block non-empty either way

      final withQuery = (await buildInjection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Sam',
        queryText: 'remember the lighthouse?',
      )).text;
      expect(withQuery, contains('the lighthouse trip'));

      final rewarmed = (await store.cardsFor('s1', 'mara'))
          .firstWhere((c) => c.content == 'the lighthouse trip');
      expect(rewarmed.heat, JournalPhysics.kRewarmHeat);
      expect(rewarmed.accessCount, 1);
    });

    test('no query or dissimilar vector leaves cold cards buried', () async {
      final cold = await addOne('unrelated memory');
      await db.updateJournalCard(
        cold.id,
        JournalMemoriesCompanion(
          heat: const Value(0.1),
          embedding: Value(_vecBytes([0, 1])), // orthogonal to the fake query
          dimensions: const Value(2),
        ),
      );
      await addOne('still warm');

      final noQuery = (await buildInjection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Sam',
      )).text;
      expect(noQuery, isNot(contains('unrelated memory')));

      final dissimilar = (await buildInjection().buildJournalBlock(
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Sam',
        queryText: 'anything at all',
      )).text;
      expect(dissimilar, isNot(contains('unrelated memory')));
      // And the buried card was never counted as accessed.
      final untouched = (await store.cardsFor('s1', 'mara'))
          .firstWhere((c) => c.content == 'unrelated memory');
      expect(untouched.accessCount, 0);
    });
  });
}
