// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';

StoopCard _card(String id, {int score = 0, int downloads = 0}) => StoopCard(
  id: id,
  name: 'Card $id',
  summary: 'summary',
  type: 'SOLO',
  nsfw: false,
  score: score,
  downloadCount: downloads,
  modPick: true,
  creator: const StoopCreatorRef(id: 'c1', displayName: 'Creator'),
  primaryAssetId: 'asset-1',
  tokenCount: 1234,
);

void main() {
  group('StoopCardStats', () {
    test('parses a cardStats frame and tolerates missing fields', () {
      final full = StoopCardStats.fromJson(const {
        'type': 'cardStats',
        'cardId': 'abc',
        'score': 7,
        'downloadCount': 42,
      });
      expect(full.cardId, 'abc');
      expect(full.score, 7);
      expect(full.downloadCount, 42);

      // Defensive floor: unknown/missing fields must not throw.
      final empty = StoopCardStats.fromJson(const {'type': 'cardStats'});
      expect(empty.cardId, '');
      expect(empty.score, 0);
      expect(empty.downloadCount, 0);
    });

    test('applyTo patches every matching card and reports a change', () {
      final cards = [_card('a'), _card('b', score: 3), _card('a', score: 1)];
      const stats = StoopCardStats(cardId: 'a', score: 5, downloadCount: 9);

      expect(stats.applyTo(cards), isTrue);
      expect(cards[0].score, 5);
      expect(cards[0].downloadCount, 9);
      expect(cards[2].score, 5);
      // Non-matching card untouched.
      expect(cards[1].score, 3);
      expect(cards[1].downloadCount, 0);
    });

    test('applyTo leaves non-matching and empty lists alone', () {
      final cards = [_card('x')];
      const stats = StoopCardStats(cardId: 'a', score: 5, downloadCount: 9);
      expect(stats.applyTo(cards), isFalse);
      expect(cards[0].score, 0);
      // The pre-load `const []` placeholders must not throw.
      expect(stats.applyTo(const []), isFalse);
    });

    test('withStats swaps counters and preserves every other field', () {
      final updated = _card('a').withStats(score: -2, downloadCount: 11);
      expect(updated.score, -2);
      expect(updated.downloadCount, 11);
      expect(updated.id, 'a');
      expect(updated.name, 'Card a');
      expect(updated.summary, 'summary');
      expect(updated.type, 'SOLO');
      expect(updated.nsfw, isFalse);
      expect(updated.modPick, isTrue);
      expect(updated.creator?.displayName, 'Creator');
      expect(updated.primaryAssetId, 'asset-1');
      expect(updated.tokenCount, 1234);
    });
  });
}
