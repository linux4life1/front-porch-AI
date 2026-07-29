// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';

void main() {
  test('round-trips world + biome in .fpworld envelope', () {
    final world = World(
      id: 'abc-123',
      name: 'Mars',
      description: 'Red dust and thin air.',
      lorebook: Lorebook(
        entries: [
          LorebookEntry(key: 'colony', content: 'SpaceX habitat domes.'),
        ],
      ),
      biomeId: 'desert',
    );
    final json = encodeFpWorld(
      world: world,
      biome: Biome.desert.toJson(),
    );
    expect(json['formatVersion'], kFpWorldFormatVersion);
    expect(json['biome']['id'], 'desert');
    expect(json['lorebooks'], isA<List>());

    final package = decodeFpWorld(json);
    expect(package.world.name, 'Mars');
    expect(package.world.description, contains('Red dust'));
    expect(package.world.lorebook.entries.single.key, 'colony');
    expect(package.biome?['id'], 'desert');
  });

  test('bare lorebook imports as degenerate world', () {
    final package = decodeFpWorld({
      'name': 'Colony Lore',
      'entries': {
        '0': {
          'uid': 1,
          'key': ['Elon'],
          'content': 'Founder energy.',
          'enabled': true,
        },
      },
    });
    expect(package.biome, isNull);
    expect(package.world.name, 'Colony Lore');
  });
}
