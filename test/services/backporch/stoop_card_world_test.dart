// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WORLD-type Stoop cards: the third card type (portable .fpworld places) must
// parse defensively alongside SOLO/GROUP and expose the isWorld/isGroup
// getters the tiles, browse filters, and download paths branch on.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/backporch/stoop_card.dart';

void main() {
  test('StoopCard parses a WORLD card and exposes isWorld', () {
    final card = StoopCard.fromJson({
      'id': 'w1',
      'name': 'Mars Colony',
      'summary': 'A dusty red frontier town.',
      'type': 'WORLD',
      'nsfw': false,
      'score': 3,
      'downloadCount': 7,
      'modPick': false,
      'primaryAssetId': 'asset-1',
    });
    expect(card.isWorld, isTrue);
    expect(card.isGroup, isFalse);
    // Live-stat patches must keep the type (worlds tick counters too).
    final patched = card.withStats(score: 9, downloadCount: 8);
    expect(patched.isWorld, isTrue);
    expect(patched.score, 9);
  });

  test('StoopCardDetail parses a WORLD card with an .fpworld payload', () {
    final detail = StoopCardDetail.fromJson({
      'id': 'w1',
      'name': 'Mars Colony',
      'summary': 'A dusty red frontier town.',
      'type': 'WORLD',
      'nsfw': false,
      'score': 0,
      'downloadCount': 0,
      'version': 1,
      'card': {
        'formatVersion': 1,
        'id': 'pkg-1',
        'name': 'Mars Colony',
        'description': 'Thin air, heavy dust.',
        'lorebook': {'entries': []},
      },
      'tags': ['scifi'],
      'primaryAssetId': 'asset-1',
      'myVote': 0,
    });
    expect(detail.isWorld, isTrue);
    expect(detail.isGroup, isFalse);
    expect(detail.card['formatVersion'], 1);
  });

  test('missing type still defaults to SOLO (mixed-fleet tolerance)', () {
    final card = StoopCard.fromJson({'id': 'x', 'name': 'n'});
    expect(card.type, 'SOLO');
    expect(card.isWorld, isFalse);
  });

  test('stoopWorldClimateEnabled missing key is ON', () {
    expect(stoopWorldClimateEnabled({}), isTrue);
    expect(stoopWorldClimateEnabled({'name': 'Old'}), isTrue);
  });

  test('stoopWorldClimateEnabled reads bool, camelCase, and 0/1', () {
    expect(stoopWorldClimateEnabled({'climate_enabled': true}), isTrue);
    expect(stoopWorldClimateEnabled({'climate_enabled': false}), isFalse);
    expect(stoopWorldClimateEnabled({'climateEnabled': false}), isFalse);
    expect(stoopWorldClimateEnabled({'climate_enabled': 0}), isFalse);
    expect(stoopWorldClimateEnabled({'climate_enabled': 1}), isTrue);
  });

  test('StoopCard.fromJson keeps WORLD envelope for climate pills', () {
    final card = StoopCard.fromJson({
      'id': 'w1',
      'name': 'Mars Colony',
      'type': 'WORLD',
      'card': {'climate_enabled': false},
    });
    expect(card.isWorld, isTrue);
    expect(stoopWorldClimateEnabled(card.card), isFalse);
  });
}
