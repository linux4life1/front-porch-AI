// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// climateEnabled: false is a lorebook-only world — description still
// injects, atmosphere/gravity stance lines do not.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';

void main() {
  World soulSociety({
    bool climate = false,
    WorldAtmosphere atmosphere = WorldAtmosphere.thin,
    WorldGravity gravity = WorldGravity.low,
  }) =>
      World(
          name: 'Soul Society',
          description: 'The afterlife realm of departed souls.',
          lorebook: Lorebook(
            entries: [
              LorebookEntry(
                key: 'Gotei 13',
                content: 'Thirteen court guard divisions.',
              ),
            ],
          ),
          climateEnabled: climate,
        )
        ..atmosphere = atmosphere
        ..gravity = gravity;

  test('climate off keeps description and drops atmosphere/gravity lines', () {
    final text = buildWorldInjection([soulSociety()]);
    expect(text, contains('Soul Society'));
    expect(text, contains('afterlife realm'));
    expect(text, isNot(contains('thin')));
    expect(text, isNot(contains('labored')));
    expect(text, isNot(contains('Gravity is low')));
    expect(text, isNot(contains('bounding strides')));
  });

  test('climate on still injects place-trait stance lines', () {
    final text = buildWorldInjection([soulSociety(climate: true)]);
    expect(text, contains('afterlife realm'));
    expect(text, contains('thin'));
    expect(text, contains('Gravity is low'));
  });

  test('climate off with no description injects nothing from this world', () {
    final world = World(
      name: 'Soul Society',
      description: '',
      lorebook: Lorebook(entries: []),
      climateEnabled: false,
      injectDescription: true,
    )..atmosphere = WorldAtmosphere.hostile;
    expect(buildWorldInjection([world]), isEmpty);
  });
}
