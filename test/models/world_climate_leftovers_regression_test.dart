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

import 'package:front_porch_ai/models/models.dart';

void main() {
  group('climate-off wire boundaries', () {
    test('World.toJson omits every leftover climate field', () {
      final world = World(
        name: 'Lore Shelf',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
        biomeId: 'custom',
        biomeJson: '{"id":"custom"}',
        placeTraits: {'atmosphere': 'unbreathable', 'gravity': 'low'},
      );

      final json = world.toJson();

      expect(json['climate_enabled'], isFalse);
      expect(json, isNot(contains('biome_id')));
      expect(json, isNot(contains('biome_json')));
      expect(json, isNot(contains('place_traits')));
      expect(world.biomeId, 'custom');
      expect(world.placeTraits, isNotEmpty);
    });

    test('World.fromJson ignores climate fields when the flag is off', () {
      final world = World.fromJson({
        'name': 'Lore Shelf',
        'lorebook': {'entries': []},
        'climate_enabled': false,
        'biome_id': 'desert',
        'biome_json': {'id': 'custom'},
        'place_traits': {'gravity': 'low'},
      });

      expect(world.climateEnabled, isFalse);
      expect(world.biomeId, isNull);
      expect(world.biomeJson, isNull);
      expect(world.placeTraits, isEmpty);
    });

    test('decodeFpWorld ignores leftover biome and traits when off', () {
      final package = decodeFpWorld({
        'formatVersion': 1,
        'id': 'lore-1',
        'name': 'Lore Shelf',
        'lorebook': {'entries': []},
        'climate_enabled': false,
        'biome': {'id': 'desert', 'displayName': 'Desert'},
        'place_traits': {'atmosphere': 'thin'},
      });

      expect(package.world.climateEnabled, isFalse);
      expect(package.biome, isNull);
      expect(package.world.placeTraits, isEmpty);
    });

    test('numeric zero and a fallback alias remain lore-only', () {
      final world = World.fromJson({
        'name': 'Lore Shelf',
        'lorebook': {'entries': []},
        'climate_enabled': 'invalid',
        'climateEnabled': 0,
        'biome_id': 'desert',
      });
      final package = decodeFpWorld({
        'formatVersion': 1,
        'name': 'Lore Shelf',
        'lorebook': {'entries': []},
        'climate_enabled': 0,
        'biome': {'id': 'desert'},
      });

      expect(world.climateEnabled, isFalse);
      expect(world.biomeId, isNull);
      expect(package.world.climateEnabled, isFalse);
      expect(package.biome, isNull);
    });
  });

  group('climate-on compatibility', () {
    test('World.toJson keeps active climate fields', () {
      final world = World(
        name: 'Weathered Place',
        lorebook: Lorebook(entries: []),
        biomeId: 'desert',
        biomeJson: '{"id":"desert"}',
        placeTraits: {'gravity': 'low'},
      );

      final json = world.toJson();

      expect(json['climate_enabled'], isTrue);
      expect(json['biome_id'], 'desert');
      expect(json['biome_json'], '{"id":"desert"}');
      expect(json['place_traits'], {'gravity': 'low'});
    });

    test('legacy full envelope without a flag keeps its biome and traits', () {
      final package = decodeFpWorld({
        'formatVersion': 1,
        'id': 'legacy-1',
        'name': 'Legacy Place',
        'lorebook': {'entries': []},
        'biome': {'id': 'desert', 'displayName': 'Desert'},
        'place_traits': {'gravity': 'low'},
      });

      expect(package.world.climateEnabled, isTrue);
      expect(package.biome?['id'], 'desert');
      expect(package.world.placeTraits, {'gravity': 'low'});
    });
  });
}
