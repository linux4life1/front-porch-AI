// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Train B — promise & debt ledger: pure parse/gate + plant/resolve integration.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/promise_debt_service.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/promise_debt_injection.dart';
import 'package:front_porch_ai/models/character_card.dart';

void main() {
  group('PromiseDebtService.warrantsEval', () {
    test('open promises always warrant a pass', () {
      expect(
        PromiseDebtService.warrantsEval('hello there', hasOpen: true),
        isTrue,
      );
    });

    test('keyword hits without open still warrant', () {
      expect(
        PromiseDebtService.warrantsEval(
          'I promise I will tell you tomorrow',
          hasOpen: false,
        ),
        isTrue,
      );
      expect(
        PromiseDebtService.warrantsEval(
          "You said you'd be honest with me",
          hasOpen: false,
        ),
        isTrue,
      );
    });

    test('ordinary chat does not warrant', () {
      expect(
        PromiseDebtService.warrantsEval(
          'We walked to the market and bought bread.',
          hasOpen: false,
        ),
        isFalse,
      );
    });
  });

  group('PromiseDebtService.parseVerdict', () {
    test('NONE / garbage → PromiseNone', () {
      expect(
        PromiseDebtService.parseVerdict('NONE', openCount: 2),
        isA<PromiseNone>(),
      );
      expect(
        PromiseDebtService.parseVerdict('maybe something', openCount: 2),
        isA<PromiseNone>(),
      );
      expect(
        PromiseDebtService.parseVerdict(null, openCount: 0),
        isA<PromiseNone>(),
      );
    });

    test('NEW user/char with description', () {
      final u = PromiseDebtService.parseVerdict(
        'NEW user tell the truth about the letter',
        openCount: 0,
      );
      expect(u, isA<PromiseNew>());
      u as PromiseNew;
      expect(u.party, 'user');
      expect(u.text, contains('letter'));

      final c = PromiseDebtService.parseVerdict(
        'NEW char: protect them from the guild',
        openCount: 0,
      );
      expect(c, isA<PromiseNew>());
      expect((c as PromiseNew).party, 'char');
    });

    test('KEPT / BROKEN with index bounds', () {
      final k = PromiseDebtService.parseVerdict('KEPT 1', openCount: 2);
      expect(k, isA<PromiseResolved>());
      expect((k as PromiseResolved).kept, isTrue);
      expect(k.index, 1);

      final b = PromiseDebtService.parseVerdict('BROKEN 2', openCount: 2);
      expect(b, isA<PromiseResolved>());
      expect((b as PromiseResolved).kept, isFalse);

      expect(
        PromiseDebtService.parseVerdict('KEPT 9', openCount: 2),
        isA<PromiseNone>(),
      );
    });
  });

  group('PromiseDebtService evaluateTurn integration', () {
    late AppDatabase db;
    late JournalStore store;
    late List<int> trustDeltas;
    late List<int> bondDeltas;

    setUp(() async {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
      trustDeltas = [];
      bondDeltas = [];
    });

    tearDown(() async {
      await db.close();
    });

    PromiseDebtService svc(Future<String?> Function(String) fire) =>
        PromiseDebtService(
          journalStore: store,
          fireEval: fire,
          getMaxCards: () => 50,
          applyTrustDelta: trustDeltas.add,
          applyBondDelta: bondDeltas.add,
        );

    test('NEW user plants open promise card', () async {
      final s = svc((_) async => 'NEW user tell her about the letter');
      await s.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben: I promise I will tell you about the letter.',
        receiptPosition: 4,
        storyDay: 1,
      );
      final open = await s.listOpen('s1', 'mara');
      expect(open, hasLength(1));
      expect(open.single.party, 'user');
      expect(open.single.text.toLowerCase(), contains('letter'));
      final cards = await store.cardsFor('s1', 'mara');
      final meta = PromiseDebtService.metaOf(cards.single.metadata);
      expect(meta['kind'], 'promise');
      expect(meta['status'], 'open');
    });

    test('BROKEN user applies trust+bond and plants milestone', () async {
      final plant = svc((_) async => 'NEW user keep the secret');
      await plant.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben: I promise to keep the secret.',
      );
      final s = svc((_) async => 'BROKEN 1');
      // Warm from same store — re-list open
      await s.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben: Actually I already told everyone.',
        receiptPosition: 9,
      );
      expect(trustDeltas, contains(PromiseDebtService.kBrokenUserTrust));
      expect(bondDeltas, contains(PromiseDebtService.kBrokenUserBond));
      final open = await s.listOpen('s1', 'mara');
      expect(open, isEmpty);
      final cards = await store.cardsFor('s1', 'mara');
      final kinds = cards
          .map((c) => PromiseDebtService.metaOf(c.metadata)['kind'])
          .toList();
      expect(kinds, contains('promise'));
      expect(kinds, contains('milestone'));
      final resolved = cards.where((c) {
        final m = PromiseDebtService.metaOf(c.metadata);
        return m['kind'] == 'promise' && m['status'] == 'broken';
      });
      expect(resolved, isNotEmpty);
    });

    test('KEPT user warms trust without inventing when NONE', () async {
      final plant = svc((_) async => 'NEW user pick her up at six');
      await plant.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben: I promise I will pick you up at six.',
      );
      final s = svc((_) async => 'KEPT 1');
      await s.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben arrives at six as promised.',
      );
      expect(trustDeltas, contains(PromiseDebtService.kKeptUserTrust));
      expect(bondDeltas, contains(PromiseDebtService.kKeptUserBond));
    });

    test('NONE does nothing even with keyword hit', () async {
      final s = svc((_) async => 'NONE');
      await s.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben: I promise nothing specific here.',
      );
      expect(await s.listOpen('s1', 'mara'), isEmpty);
      expect(trustDeltas, isEmpty);
    });

    test('char broken moves bond only (not trust)', () async {
      final plant = svc((_) async => 'NEW char protect him from the guild');
      await plant.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Mara: I swear I will protect you from the guild.',
      );
      final s = svc((_) async => 'BROKEN 1');
      await s.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Mara sold him out to the guild.',
      );
      expect(trustDeltas, isEmpty);
      expect(bondDeltas, contains(PromiseDebtService.kBrokenCharBond));
    });
  });

  group('PromiseDebtInjection', () {
    late AppDatabase db;
    late JournalStore store;
    late PromiseDebtService service;

    setUp(() async {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
      service = PromiseDebtService(
        journalStore: store,
        fireEval: (_) async => 'NEW user tell the truth',
        getMaxCards: () => 50,
        applyTrustDelta: (_) {},
        applyBondDelta: (_) {},
      );
      await service.evaluateTurn(
        sessionId: 's1',
        characterId: 'mara',
        characterName: 'Mara',
        userName: 'Ben',
        recentExchange: 'Ben: I promise I will tell the truth.',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('builds words-only open commitment line', () {
      final inj = PromiseDebtInjection(
        promiseDebtService: service,
        getSessionId: () => 's1',
        getActiveCharacter: () => CharacterCard(name: 'Mara'),
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => 'mara',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => 'mara',
        getUserName: () => 'Ben',
      );
      // Cache may still be warming — force list into cache.
      expect(service.cachedOpen('s1', 'mara'), isNotNull);
      final line = inj.buildPromiseDebtInjection();
      expect(line, contains('Open commitments'));
      expect(line, contains('Ben'));
      expect(RegExp(r'\d{2,}').hasMatch(line), isFalse); // no score dumps
    });
  });
}
