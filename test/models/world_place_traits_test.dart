// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Place traits (living-worlds.md §3 Rev.3): atmosphere/gravity enums on the
// WORLD — silent defaults, code-owned injected lines, future-proof raw map,
// .fpworld carriage.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';

World _world({String desc = 'A red desert.', bool inject = true}) => World(
  name: 'Mars',
  description: desc,
  lorebook: Lorebook(entries: []),
  injectDescription: inject,
);

void main() {
  group('World place traits model', () {
    test('defaults are silent: empty map, omitted from JSON', () {
      final w = _world();
      expect(w.atmosphere, WorldAtmosphere.breathable);
      expect(w.gravity, WorldGravity.earth);
      expect(w.toJson().containsKey('place_traits'), isFalse);
    });

    test('non-defaults round-trip; resetting to default removes the key', () {
      final w = _world()
        ..atmosphere = WorldAtmosphere.unbreathable
        ..gravity = WorldGravity.low;
      final back = World.fromJson(w.toJson());
      expect(back.atmosphere, WorldAtmosphere.unbreathable);
      expect(back.gravity, WorldGravity.low);
      back.atmosphere = WorldAtmosphere.breathable;
      expect(back.placeTraits.containsKey('atmosphere'), isFalse);
    });

    test('unknown trait keys survive a round-trip (mixed-fleet rule)', () {
      final w = _world();
      w.placeTraits['magnetosphere'] = 'none';
      w.atmosphere = WorldAtmosphere.thin;
      final back = World.fromJson(w.toJson());
      expect(back.placeTraits['magnetosphere'], 'none');
      expect(back.atmosphere, WorldAtmosphere.thin);
    });

    test('garbage trait values degrade to defaults, never throw', () {
      final w = World.fromJson({
        'name': 'X',
        'lorebook': Lorebook(entries: []).toJson(),
        'place_traits': {'atmosphere': 42, 'gravity': 'sideways'},
      });
      expect(w.atmosphere, WorldAtmosphere.breathable);
      expect(w.gravity, WorldGravity.earth);
    });
  });

  group('place trait injection', () {
    test('default traits add nothing to the setting block', () {
      final out = buildWorldInjection([_world()]);
      expect(out, contains('A red desert.'));
      expect(out, isNot(contains('air')));
      expect(out, isNot(contains('Gravity')));
    });

    test('non-default traits inject one code-owned line each', () {
      final w = _world()
        ..atmosphere = WorldAtmosphere.unbreathable
        ..gravity = WorldGravity.low;
      final out = buildWorldInjection([w]);
      expect(out, contains('unbreathable'));
      expect(out, contains('airlock'));
      expect(out, contains('Gravity is low'));
    });

    test('trait lines ride even when description injection is OFF', () {
      final w = _world(inject: false)..atmosphere = WorldAtmosphere.hostile;
      final out = buildWorldInjection([w]);
      expect(out, isNot(contains('A red desert.')));
      expect(out, contains('hostile'));
    });

    test('under budget pressure the description truncates, traits survive', () {
      final w = _world(desc: 'x' * (kWorldInjectionMaxChars + 200))
        ..atmosphere = WorldAtmosphere.unbreathable;
      final out = buildWorldInjection([_world(desc: 'y' * 100), w]);
      expect(
        out,
        contains('airlock'),
        reason: 'behavior beats flavor under the cap',
      );
      expect(out.length, lessThan(kWorldInjectionMaxChars + 200));
    });

    test('a fully-silent world injects nothing at all', () {
      expect(buildWorldInjection([_world(desc: '', inject: false)]), '');
    });
  });

  group('.fpworld carriage', () {
    test('envelope carries traits and decode restores them', () {
      final w = _world()..gravity = WorldGravity.micro;
      final envelope = encodeFpWorld(world: w, biome: null);
      expect(envelope['place_traits'], isNotNull);
      final decoded = decodeFpWorld(envelope);
      expect(decoded.world.gravity, WorldGravity.micro);
    });

    test('trait-less envelope omits the key (older readers unchanged)', () {
      final envelope = encodeFpWorld(world: _world(), biome: null);
      expect(envelope.containsKey('place_traits'), isFalse);
    });
    test('a climate-off place keeps its ambience on an export round-trip', () {
      final w = _world()
        ..climateEnabled = false
        ..ambience = 'forest';
      final envelope = encodeFpWorld(world: w, biome: null);
      expect(envelope['ambience'], 'forest');
      expect(envelope.containsKey('place_traits'), isFalse);
      final decoded = decodeFpWorld(envelope);
      expect(decoded.world.climateEnabled, isFalse);
      expect(decoded.world.ambience, 'forest');
    });

    test('a custom ambience file never rides an export', () {
      final w = _world()
        ..climateEnabled = true
        ..ambience = 'forest'
        ..customAmbience = 'my_room.mp3';
      final envelope = encodeFpWorld(world: w, biome: null);
      expect(envelope['ambience'], 'forest');
      expect(
        (envelope['place_traits'] as Map).containsKey('customAmbience'),
        isFalse,
      );
      final decoded = decodeFpWorld(envelope);
      expect(decoded.world.customAmbience, isNull);
      expect(decoded.world.ambience, 'forest');
    });
  });

  group('a weather-off top-level world', () {
    World place() => World(
      name: 'The Greenhouse',
      description: 'Warm glass rooms.',
      lorebook: Lorebook(entries: []),
      parentWorldId: 'earth',
    )..atmosphere = WorldAtmosphere.thin;

    test('silences the traits of a place that owns a climate', () {
      final earth = _world()..climateEnabled = false;
      final out = buildWorldInjection([place(), earth]);
      expect(out, contains('Warm glass rooms.'));
      expect(out, isNot(contains('air is thin')));
    });

    test('the same place speaks its traits once the root is on', () {
      final earth = _world();
      final out = buildWorldInjection([place(), earth]);
      expect(out, contains('air is thin'));
    });
  });
}
