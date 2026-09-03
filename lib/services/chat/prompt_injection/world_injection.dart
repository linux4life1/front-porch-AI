// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World description injection — makes a world a *place* the character inhabits.
// Budget-capped; only worlds with injectDescription == true contribute.

import 'package:front_porch_ai/models/models.dart';

/// Soft token budget for world place prose (approx chars / 4).
const int kWorldInjectionMaxChars = 600;

/// Code-owned behavior line per non-default atmosphere (living-worlds.md §3
/// Rev.3 place traits — the stance recipe: the app writes the behavior, the
/// author's prose is garnish). Defaults are silent.
String? atmosphereLine(WorldAtmosphere a) => switch (a) {
  WorldAtmosphere.breathable => null,
  WorldAtmosphere.thin =>
    'The air is thin — unassisted breathing is labored, and real exertion '
        'needs masks or acclimatization.',
  WorldAtmosphere.unbreathable =>
    'The air is unbreathable — no one steps outside unsealed; the airlock '
        'is a ritual, not a door.',
  WorldAtmosphere.hostile =>
    'The air itself is hostile — exposure damages skin and equipment, and '
        'time outside is rationed and urgent.',
};

/// Code-owned behavior line per non-default gravity. Defaults are silent.
String? gravityLine(WorldGravity g) => switch (g) {
  WorldGravity.earth => null,
  WorldGravity.low =>
    'Gravity is low — bounding strides come easy, and dropped things fall '
        'lazily.',
  WorldGravity.high =>
    'Gravity is high — every limb is heavy, and effort taxes twice as fast.',
  WorldGravity.micro =>
    'There is almost no gravity — nothing stays down; people float, tether, '
        'and drift.',
};

/// Build a scene-setting block from attached worlds' descriptions + place
/// traits. Empty when nothing should inject. Trait lines are behavioral
/// instructions, so they ride even when the description is empty or its
/// injection is toggled off — the author picked them explicitly.
String buildWorldInjection(List<World> worlds) {
  final parts = <String>[];
  var used = 0;
  for (final w in worlds) {
    final desc = w.injectDescription ? w.description.trim() : '';
    // Lorebook-only worlds carry no physical-world traits.
    final traits = w.climateEnabled
        ? [
            atmosphereLine(w.atmosphere),
            gravityLine(w.gravity),
          ].nonNulls.join(' ')
        : '';
    if (desc.isEmpty && traits.isEmpty) continue;
    final header = w.name.trim().isEmpty ? 'This place' : w.name.trim();
    final body = [
      if (desc.isNotEmpty) desc,
      if (traits.isNotEmpty) traits,
    ].join(' ');
    final block = '$header: $body';
    if (used + block.length > kWorldInjectionMaxChars) {
      final remain = kWorldInjectionMaxChars - used;
      if (remain < 40) break;
      // Truncate the description, never the trait lines: behavior beats
      // flavor under budget pressure.
      final descBudget = remain - traits.length - header.length - 2;
      if (traits.isNotEmpty && descBudget > 0 && desc.isNotEmpty) {
        final cut = desc.length > descBudget
            ? desc.substring(0, descBudget).trimRight()
            : desc;
        parts.add('$header: $cut $traits');
      } else if (traits.isNotEmpty && remain >= traits.length + header.length) {
        parts.add('$header: $traits');
      } else {
        parts.add(block.substring(0, remain).trimRight());
      }
      break;
    }
    parts.add(block);
    used += block.length + 1;
  }
  if (parts.isEmpty) return '';
  return 'Setting — where you are:\n${parts.join('\n')}';
}
