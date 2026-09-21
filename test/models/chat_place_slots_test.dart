// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Primary / Lore place slot helpers.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/chat_place_slots.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';

void main() {
  group('partitionLinkedPlaces', () {
    test('first climate-enabled becomes primary; rest lore', () {
      final slots = partitionLinkedPlaces(
        worldIds: ['a', 'b', 'c'],
        isClimateEnabled: (id) => id == 'b' || id == 'c',
      );
      expect(slots.primaryId, 'b');
      expect(slots.loreIds, ['a', 'c']);
    });

    test('all climate-off → primary empty, all lore', () {
      final slots = partitionLinkedPlaces(
        worldIds: ['x', 'y'],
        isClimateEnabled: (_) => false,
      );
      expect(slots.primaryId, isNull);
      expect(slots.loreIds, ['x', 'y']);
    });
  });

  group('primaryWorldAllowsClimate', () {
    World place({required bool climate}) => World(
          name: 'P',
          lorebook: Lorebook(entries: []),
          climateEnabled: climate,
        );

    test('primary empty → weather off', () {
      expect(primaryWorldAllowsClimate(null), isFalse);
    });

    test('primary climate-on → weather on', () {
      expect(primaryWorldAllowsClimate(place(climate: true)), isTrue);
    });

    test('primary climate-off → weather off', () {
      expect(primaryWorldAllowsClimate(place(climate: false)), isFalse);
    });
  });

  group('attachedWorldsAllowClimate (legacy)', () {
    World place({required bool climate, String name = 'P'}) => World(
          name: name,
          lorebook: Lorebook(entries: []),
          climateEnabled: climate,
        );

    test('no attached worlds → weather off (no temperate fallback)', () {
      expect(attachedWorldsAllowClimate(const []), isFalse);
    });

    test('lore-only list still reports climate if any climate-on present', () {
      // Legacy helper is flat; weather gate must use primaryWorldAllowsClimate.
      expect(
        attachedWorldsAllowClimate([
          place(name: 'Mars', climate: true),
        ]),
        isTrue,
      );
    });
  });
}
