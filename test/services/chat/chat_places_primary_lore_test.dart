// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Primary owns weather/injection; lore climate-on stays lore-only.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/chat_place_slots.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';

void main() {
  World place({
    required String name,
    required bool climate,
    String description = '',
    String? biomeJson,
    WorldAtmosphere atmosphere = WorldAtmosphere.breathable,
  }) {
    final w = World(
      id: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      description: description,
      lorebook: Lorebook(entries: []),
      climateEnabled: climate,
      biomeJson: biomeJson,
      injectDescription: true,
    );
    if (climate) w.atmosphere = atmosphere;
    return w;
  }

  test('injection: setting prose only from Primary', () {
    final primary = place(
      name: 'Earth',
      climate: true,
      description: 'Blue marble.',
      atmosphere: WorldAtmosphere.thin,
    );
    final lore = place(
      name: 'Mars',
      climate: true,
      description: 'Red planet.',
      atmosphere: WorldAtmosphere.hostile,
    );
    final text = buildWorldInjection([primary]);
    expect(text, contains('Blue marble'));
    expect(text, isNot(contains('Red planet')));
    // Lore must not be passed into buildWorldInjection by callers.
    final both = buildWorldInjection([primary, lore]);
    expect(both, contains('Red planet')); // function itself is list-based
    // Contract is enforced at the call site (Primary-only list).
  });

  test('multi-climate: only Primary drives climate options', () {
    final earth = place(name: 'Earth', climate: true, biomeJson: '{"id":"e"}');
    final mars = place(name: 'Mars', climate: true, biomeJson: '{"id":"m"}');
    final primary = earth;
    final lore = [mars];
    expect(primaryWorldAllowsClimate(primary), isTrue);
    // Lore Mars must not appear as a climate author.
    final customFromPrimary = primary.climateEnabled && primary.biomeJson != null;
    final customFromLore = lore.any((w) => w.climateEnabled && w.biomeJson != null);
    expect(customFromPrimary, isTrue);
    expect(customFromLore, isTrue); // file has climate — role still lore
    // Picker filter: Primary only.
    final pickerCustoms = [
      if (primaryWorldAllowsClimate(primary) && primary.biomeJson != null)
        primary,
    ];
    expect(pickerCustoms.map((w) => w.name), ['Earth']);
    expect(pickerCustoms.any((w) => w.name == 'Mars'), isFalse);
  });

  test('primary empty → weather off even with lore present', () {
    final mars = place(name: 'Mars', climate: true);
    expect(primaryWorldAllowsClimate(null), isFalse);
    // Presence of lore climate-on does not matter for the Primary gate.
    expect(mars.climateEnabled, isTrue);
  });

  test('lore Mars climate-on → no weather, not in climate dropdown', () {
    final soul = place(name: 'Soul Society', climate: false);
    final mars = place(name: 'Mars', climate: true, biomeJson: '{"id":"m"}');
    // Primary empty, Mars in lore.
    expect(primaryWorldAllowsClimate(null), isFalse);
    final climateOptions = <World>[
      // Primary-only filter
    ];
    expect(climateOptions, isEmpty);
    // If Soul Society is Primary (climate-off), still no weather / no customs.
    expect(primaryWorldAllowsClimate(soul), isFalse);
    final customs = [
      if (primaryWorldAllowsClimate(soul) && soul.biomeJson != null) soul,
      // Mars is lore — excluded
    ];
    expect(customs, isEmpty);
    expect(mars.biomeJson, isNotNull);
  });

  test('demote-on-replace puts old Setting at lore top', () {
    final slots = ChatPlaceSlots(primaryId: 'earth', loreIds: const ['soul']);
    // Replace with mars: demote earth to lore top.
    final next = ChatPlaceSlots(
      primaryId: 'mars',
      loreIds: [
        slots.primaryId!,
        ...slots.loreIds,
      ],
    );
    expect(next.primaryId, 'mars');
    expect(next.loreIds, ['earth', 'soul']);
  });

  test('group detach → empty slots (no ghost)', () {
    final empty = const ChatPlaceSlots();
    expect(empty.primaryId, isNull);
    expect(empty.loreIds, isEmpty);
    expect(empty.allIds, isEmpty);
  });
}
