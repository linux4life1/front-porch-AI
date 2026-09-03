// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// .fpworld carriage of climate_enabled. A lorebook-only world exports
// the flag off and no biome; import tolerates a missing biome.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';

void main() {
  test(
    'lorebook-only envelope round-trips climate_enabled false without biome',
    () {
      final world = World(
        id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        name: 'Soul Society',
        description: 'The afterlife realm of departed souls...',
        lorebook: Lorebook(
          entries: [
            LorebookEntry(
              key: 'Seireitei',
              content: 'The walled city of souls.',
            ),
          ],
        ),
        climateEnabled: false,
      );
      final json = encodeFpWorld(world: world, biome: null);
      expect(json['climate_enabled'], isFalse);
      expect(json.containsKey('biome'), isFalse);

      final decoded = decodeFpWorld(json);
      expect(decoded.world.climateEnabled, isFalse);
      expect(decoded.biome, isNull);
      expect(decoded.world.name, 'Soul Society');
      expect(decoded.world.lorebook.entries.single.key, 'Seireitei');
    },
  );

  test('import of climate-off envelope with no biome key does not throw', () {
    final package = decodeFpWorld({
      'formatVersion': 1,
      'id': 'ss-1',
      'name': 'Soul Society',
      'description': 'Bookshelf world.',
      'lorebook': {
        'entries': [
          {'key': 'Gotei 13', 'content': 'Thirteen divisions.'},
        ],
      },
      'climate_enabled': false,
    });
    expect(package.world.climateEnabled, isFalse);
    expect(package.biome, isNull);
  });

  test(
    'climate-off omits leftover place_traits even when they exist in memory',
    () {
      final world = World(
        name: 'Soul Society',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
        placeTraits: {'atmosphere': 'unbreathable', 'gravity': 'low'},
      );
      final json = encodeFpWorld(
        world: world,
        biome: {'id': 'temperate'},
      );
      expect(json.containsKey('biome'), isFalse);
      expect(json.containsKey('place_traits'), isFalse);
      expect(json['climate_enabled'], isFalse);
    },
  );

  test('older envelope without the key imports as climate on', () {
    final package = decodeFpWorld({
      'formatVersion': 1,
      'id': 'mars-1',
      'name': 'Mars',
      'description': 'Red dust.',
      'lorebook': {'entries': []},
      'biome': Biome.desert.toJson(),
    });
    expect(package.world.climateEnabled, isTrue);
    expect(package.biome?['id'], 'desert');
  });
}
