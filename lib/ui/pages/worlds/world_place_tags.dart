// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Weather and climate wording shared by the world cards, the place rows
// and the places panel, so a place reads the same wherever it shows.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';

/// The inherit/own tag for a place (null for a top-level world, whose
/// climate story is its own chip). [hasWeatherToInherit] is false when
/// nothing in the chain authors weather — none owns one, or the top-level
/// world has weather off — so an owned climate there reads as paused.
String? placeWeatherTag(
  World place, {
  required bool isPlace,
  required bool hasWeatherToInherit,
}) {
  if (!isPlace) return null;
  final tag = place.climateEnabled
      ? (hasWeatherToInherit ? 'Own climate' : 'Own climate · paused')
      : hasWeatherToInherit
      ? 'Inherits weather'
      : 'Weather off';
  // A place that owns its climate names the biome, so a continent's row
  // tells its weather at a glance.
  final biome = (place.climateEnabled && hasWeatherToInherit)
      ? Biome.builtInById(place.biomeId)?.displayName
      : null;
  return biome == null ? tag : '$tag · $biome';
}

/// One line for a top-level world's weather. A custom-biome world
/// (biomeJson set, no built-in id) must not read as a bland "temperate".
String worldClimateLine(World world) {
  if (!world.climateEnabled) return 'Weather off for the whole world';
  final id = world.biomeId;
  final name = id != null && id.isNotEmpty
      ? Biome.builtInById(id)?.displayName ?? id
      : (world.biomeJson != null ? 'Custom climate' : 'temperate');
  return 'Weather: $name';
}

String entriesLabel(World world) {
  final n = world.lorebook.entries.length;
  return '$n ${n == 1 ? 'entry' : 'entries'}';
}
