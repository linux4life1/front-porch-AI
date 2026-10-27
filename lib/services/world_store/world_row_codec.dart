// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Drift row <-> model World mapping for [WorldRepository], split out to
// keep the repository under the 500-line ratchet. Pure: no cache, no DB
// calls, so the repository stays the sole owner of persistence.

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart' hide World;
import 'package:front_porch_ai/models/world.dart' as model;

/// A stored row as the model. A corrupt lorebook blob reads as an empty
/// book rather than failing the whole library load.
model.World worldFromRow(World row) {
  Lorebook lorebook;
  if (row.lorebook != null) {
    try {
      lorebook = Lorebook.fromJson(jsonDecode(row.lorebook!));
    } catch (_) {
      lorebook = Lorebook(entries: []);
    }
  } else {
    lorebook = Lorebook(entries: []);
  }
  return model.World(
    id: row.id,
    name: row.name,
    description: row.description,
    lorebook: lorebook,
    linkedCharacterName: row.linkedCharacterName,
    linkedCharacterId: row.linkedCharacterId,
    coverImage: row.coverImage,
    sourceId: row.sourceId,
    formatVersion: row.formatVersion,
    biomeId: row.biomeId,
    biomeJson: row.biomeJson,
    injectDescription: row.injectDescription,
    climateEnabled: row.climateEnabled,
    parentWorldId: row.parentWorldId,
    placeTraits: _tryDecodeMap(row.placeTraits),
  );
}

/// Defensive JSON-map decode for the place_traits column (null/garbage →
/// null → all-default traits).
Map<String, dynamic>? _tryDecodeMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

WorldsCompanion worldToCompanion(model.World world) {
  return WorldsCompanion(
    id: Value(world.id),
    name: Value(world.name),
    description: Value(world.description),
    lorebook: Value(jsonEncode(world.lorebook.toJson())),
    linkedCharacterName: Value(world.linkedCharacterName),
    linkedCharacterId: Value(world.linkedCharacterId),
    coverImage: Value(world.coverImage),
    sourceId: Value(world.sourceId),
    formatVersion: Value(world.formatVersion),
    biomeId: Value(world.biomeId),
    biomeJson: Value(world.biomeJson),
    injectDescription: Value(world.injectDescription),
    climateEnabled: Value(world.climateEnabled),
    parentWorldId: Value(world.parentWorldId),
    placeTraits: Value(
      world.placeTraits.isEmpty ? null : jsonEncode(world.placeTraits),
    ),
  );
}
