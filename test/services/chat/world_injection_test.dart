// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';

void main() {
  test('skips worlds with injectDescription false or empty desc', () {
    final text = buildWorldInjection([
      World(
        name: 'Mars',
        description: 'Dust.',
        lorebook: Lorebook(entries: []),
        injectDescription: false,
      ),
      World(
        name: 'Empty',
        description: '  ',
        lorebook: Lorebook(entries: []),
      ),
    ]);
    expect(text, isEmpty);
  });

  test('includes place prose when enabled', () {
    final text = buildWorldInjection([
      World(
        name: 'Mars',
        description: 'Red horizons and thin air.',
        lorebook: Lorebook(entries: []),
        injectDescription: true,
      ),
    ]);
    expect(text, contains('Mars'));
    expect(text, contains('Red horizons'));
    expect(text, startsWith('Setting'));
  });

  group('Location chain (slice 2)', () {
    World world(String name, {String? parent, required String description}) =>
        World(
          name: name,
          description: description,
          lorebook: Lorebook(entries: []),
          parentWorldId: parent,
          climateEnabled: false,
        );

    const header = 'Setting — where you are:\n';

    test(
      'leaf prose comes first; the parent fills what is left of the cap',
      () {
        final town = world('Bletchfield', description: 'Damp springs. ' * 60);
        final room = world(
          'Tea Rooms',
          parent: town.name,
          description: 'Steam on the windows, gossip on the saucers.',
        );
        // Order is chainFor's: leaf first. The caller builds it, not this
        // function — same contract the Primary-only rule already has.
        final text = buildWorldInjection([room, town]);
        final roomAt = text.indexOf('Steam on the windows');
        final townAt = text.indexOf('Bletchfield:');
        expect(roomAt, greaterThanOrEqualTo(0));
        expect(townAt, greaterThan(roomAt));
        expect(text.length, lessThanOrEqualTo(header.length + 600 + 1));
      },
    );

    test('a three-tier chain costs no more than the single-world cap', () {
      final town = world('Bletchfield', description: 'T' * 400);
      final house = world('Academy', parent: town.name, description: 'H' * 400);
      final room = world('Library', parent: house.name, description: 'R' * 400);
      final text = buildWorldInjection([room, house, town]);
      expect(text.length, lessThanOrEqualTo(header.length + 600 + 1));
      // The leaf is never cut: its full prose survives.
      expect(text.contains('R' * 400), isTrue);
      // The ancestor is truncated: all 400 chars of it do not fit.
      expect(text.contains('H' * 400), isFalse);
    });
  });

  group('trait lines come from the climate author only', () {
    World root() =>
        World(
            id: 'moon',
            name: 'Grey Moon',
            description: 'Dust under a black sky.',
            lorebook: Lorebook(entries: []),
          )
          ..atmosphere = WorldAtmosphere.unbreathable
          ..gravity = WorldGravity.low;

    World child({required bool climate}) => World(
      id: 'wheel',
      name: 'The Wheel',
      description: 'Parks and canals under a long sunlit strip.',
      lorebook: Lorebook(entries: []),
      parentWorldId: 'moon',
      climateEnabled: climate,
    );

    test('a place that owns its climate silences the root\'s traits', () {
      final text = buildWorldInjection([child(climate: true), root()]);
      expect(text, contains('Parks and canals'));
      expect(text, contains('Dust under a black sky.'));
      expect(text, isNot(contains('unbreathable')));
      expect(text, isNot(contains('Gravity is low')));
    });

    test('a place that inherits gets the root\'s trait lines', () {
      final text = buildWorldInjection([child(climate: false), root()]);
      expect(text, contains('unbreathable'));
      expect(text, contains('Gravity is low'));
    });

    test('a place that owns climate and traits speaks only its own', () {
      final dome = child(climate: true)..gravity = WorldGravity.high;
      final text = buildWorldInjection([dome, root()]);
      expect(text, contains('Gravity is high'));
      expect(text, isNot(contains('Gravity is low')));
      expect(text, isNot(contains('unbreathable')));
    });
  });
}
