// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Time §7 v1.5 — pure text + plant helpers for bond/trust tier cards.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/relationship_milestones.dart';

void main() {
  group('RelationshipMilestones.textFor / emotionFor', () {
    test('bond deepen / cool with distinct labels', () {
      final up = TierCrossing(
        axis: 'bond',
        oldTier: 2,
        newTier: 4,
        oldLabel: 'Receptive',
        newLabel: 'Friendly',
      );
      expect(
        RelationshipMilestones.textFor(up),
        'Bond deepened to Friendly (was Receptive).',
      );
      expect(RelationshipMilestones.emotionFor(up), 'warm');

      final down = TierCrossing(
        axis: 'bond',
        oldTier: 4,
        newTier: 2,
        oldLabel: 'Friendly',
        newLabel: 'Receptive',
      );
      expect(
        RelationshipMilestones.textFor(down),
        'Bond cooled to Receptive (was Friendly).',
      );
      expect(RelationshipMilestones.emotionFor(down), 'hurt');
    });

    test('same-label bond tiers use edged wording (0↔1 both Neutral)', () {
      final up = TierCrossing(
        axis: 'bond',
        oldTier: 0,
        newTier: 1,
        oldLabel: 'Neutral',
        newLabel: 'Neutral',
      );
      expect(
        RelationshipMilestones.textFor(up),
        'Bond edged upward (Neutral).',
      );
    });

    test('trust rose / fell wording', () {
      final up = TierCrossing(
        axis: 'trust',
        oldTier: 0,
        newTier: 2,
        oldLabel: 'Neutral',
        newLabel: 'Leaning Positive',
      );
      expect(
        RelationshipMilestones.textFor(up),
        'Trust rose to Leaning Positive (was Neutral).',
      );
      expect(RelationshipMilestones.emotionFor(up), 'relieved');

      final down = TierCrossing(
        axis: 'trust',
        oldTier: 2,
        newTier: -2,
        oldLabel: 'Leaning Positive',
        newLabel: 'Guarded',
      );
      expect(
        RelationshipMilestones.textFor(down),
        'Trust fell to Guarded (was Leaning Positive).',
      );
      expect(RelationshipMilestones.emotionFor(down), 'wary');
    });

    test('long-term bond climate wording (v1.5.1)', () {
      final up = TierCrossing(
        axis: 'long_term',
        oldTier: 2,
        newTier: 4,
        oldLabel: 'Receptive',
        newLabel: 'Friendly',
      );
      expect(
        RelationshipMilestones.textFor(up),
        'Something deeper settled — the long bond feels Friendly '
        '(was Receptive).',
      );
      expect(RelationshipMilestones.emotionFor(up), 'devoted');

      final down = TierCrossing(
        axis: 'long_term',
        oldTier: 4,
        newTier: 2,
        oldLabel: 'Friendly',
        newLabel: 'Receptive',
      );
      expect(
        RelationshipMilestones.textFor(down),
        'Something deeper cracked — the long bond feels Receptive '
        '(was Friendly).',
      );
      expect(RelationshipMilestones.emotionFor(down), 'wistful');
    });
  });

  group('RelationshipMilestones.plant', () {
    late AppDatabase db;
    late JournalStore store;

    setUp(() async {
      db = AppDatabase.forTesting();
      store = JournalStore(getDb: () => db);
    });

    tearDown(() async {
      await db.close();
    });

    test('plants kind=milestone card with content + receipt', () async {
      await RelationshipMilestones.plant(
        store: store,
        sessionId: 'sess-1',
        characterId: 'mara',
        crossing: const TierCrossing(
          axis: 'bond',
          oldTier: 3,
          newTier: 5,
          oldLabel: 'Warm',
          newLabel: 'Amiable',
        ),
        sourcePositions: const [12],
        storyDay: 2,
        storyClock: '2026-01-03T18:00:00.000Z',
        maxCards: 50,
      );
      final cards = await store.cardsFor('sess-1', 'mara');
      expect(cards, hasLength(1));
      final c = cards.single;
      expect(c.content, 'Bond deepened to Amiable (was Warm).');
      expect(c.emotionLabel, 'warm');
      expect(c.category, 'moment');
      final meta = jsonDecode(c.metadata!) as Map<String, dynamic>;
      expect(meta['kind'], 'milestone');
      expect(meta['storyDay'], 2);
      expect(jsonDecode(c.sourceMessageIds!), [12]);
    });
  });
}
