// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-world climateEnabled: default on, JSON key climate_enabled, old
// payloads without the key stay climate-on so existing worlds do not
// lose weather on upgrade. climate_enabled: false is a lorebook-only
// bookshelf world (Soul Society).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';

void main() {
  group('World.climateEnabled', () {
    test('defaults on so existing worlds keep climate', () {
      final world = World(
        name: 'Mars',
        lorebook: Lorebook(entries: []),
      );
      expect(world.climateEnabled, isTrue);
      expect(world.toJson()['climate_enabled'], isTrue);
    });

    test('fromJson missing key is treated as enabled', () {
      final world = World.fromJson({
        'name': 'Old Place',
        'lorebook': {'entries': []},
      });
      expect(world.climateEnabled, isTrue);
    });

    test('fromJson camelCase alias is accepted', () {
      final world = World.fromJson({
        'name': 'Camel',
        'lorebook': {'entries': []},
        'climateEnabled': false,
      });
      expect(world.climateEnabled, isFalse);
    });

    test('Soul Society lorebook-only JSON round-trips with climate off', () {
      const id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final world = World.fromJson({
        'id': id,
        'name': 'Soul Society',
        'description': 'The afterlife realm of departed souls...',
        'lorebook': {
          'entries': [
            {
              'key': 'Gotei 13',
              'content': 'Thirteen court guard divisions of the Seireitei.',
            },
          ],
        },
        'climate_enabled': false,
        'biome_id': null,
        'biome_json': null,
        'atmosphere': null,
        'gravity': null,
      });

      expect(world.id, id);
      expect(world.name, 'Soul Society');
      expect(world.climateEnabled, isFalse);
      expect(world.biomeId, isNull);
      expect(world.biomeJson, isNull);
      expect(world.lorebook.entries, hasLength(1));

      final json = world.toJson();
      expect(json['climate_enabled'], isFalse);
      expect(json.containsKey('biome_id'), isFalse);
      expect(json.containsKey('biome_json'), isFalse);

      final restored = World.fromJson(json);
      expect(restored.climateEnabled, isFalse);
      expect(restored.lorebook.entries.single.key, 'Gotei 13');
    });
  });

  group('attachedWorldsAllowClimate', () {
    World place({required bool climate, String name = 'P'}) => World(
      name: name,
      lorebook: Lorebook(entries: []),
      climateEnabled: climate,
    );

    test('no attached worlds keeps the temperate default running', () {
      expect(attachedWorldsAllowClimate(const []), isTrue);
    });

    test('a climate-on world keeps weather running', () {
      expect(attachedWorldsAllowClimate([place(climate: true)]), isTrue);
    });

    test('Soul Society alone silences weather', () {
      expect(
        attachedWorldsAllowClimate([
          place(name: 'Soul Society', climate: false),
        ]),
        isFalse,
      );
    });

    test('mixed attachments still run weather from the climate world', () {
      expect(
        attachedWorldsAllowClimate([
          place(name: 'Soul Society', climate: false),
          place(name: 'Karakura', climate: true),
        ]),
        isTrue,
      );
    });
  });
}
