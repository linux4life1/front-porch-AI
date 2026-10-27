// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:uuid/uuid.dart';

/// Standing facts about a place (living-worlds.md §3 Rev.3 place traits).
/// Stance-recipe enums: the default is SILENT (injects nothing, costs no
/// tokens), each non-default value maps to ONE code-owned prompt line in
/// world_injection. No numeric fields on purpose — numbers would promise a
/// simulation the app deliberately does not run.
enum WorldAtmosphere { breathable, thin, unbreathable, hostile }

enum WorldGravity { earth, low, high, micro }

WorldAtmosphere worldAtmosphereFromName(String? name) =>
    WorldAtmosphere.values.asNameMap()[name?.toLowerCase()] ??
    WorldAtmosphere.breathable;

WorldGravity worldGravityFromName(String? name) =>
    WorldGravity.values.asNameMap()[name?.toLowerCase()] ?? WorldGravity.earth;

/// Read the additive world climate flag without making malformed aliases win.
///
/// Snake case is canonical, camel case is accepted for web DTOs, and bool or
/// 0/1 values are tolerated at mixed-fleet boundaries. Null means neither
/// spelling carried a usable value, so callers can choose their own fallback.
bool? readWorldClimateEnabled(Map<String, dynamic> json) {
  for (final key in const ['climate_enabled', 'climateEnabled']) {
    final raw = json[key];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
  }
  return null;
}

/// A portable *place*: lore (and later climate) that attaches to chats, not
/// to characters. Stable [id] is the only durable reference; [name] is
/// display-only (UNIQUE in DB, auto-renamed on import collision).
class World {
  /// Stable UUID identity. Empty only for brand-new unsaved drafts.
  String id;

  String name;
  String description;
  Lorebook lorebook;

  /// Built-in biome id (e.g. `temperate`, `desert`) or null → temperate default.
  /// Custom biome JSON (phase 2) lives in [biomeJson] when set.
  String? biomeId;

  /// Full biome snapshot JSON when the world carries a non-built-in climate.
  /// Built-ins store only [biomeId]; export embeds the resolved snapshot.
  String? biomeJson;

  /// Optional cover image (path or data URL); size-capped on export.
  String? coverImage;

  /// Provenance: original package id when this world was imported.
  String? sourceId;

  int formatVersion;

  /// If set, this world was auto-created from a character import (legacy name).
  String? linkedCharacterName;

  /// Preferred over [linkedCharacterName] once backfilled.
  String? linkedCharacterId;

  /// Runtime-only avatar path resolved from the linked character.
  String? avatarPath;

  /// When false, world description is not injected into the prompt (migrated
  /// library-label worlds default off).
  bool injectDescription;

  /// When false, this world is lorebook + description only — no climate, no
  /// weather, no atmosphere/gravity place traits. Default true so existing
  /// worlds keep the weather machine plugged in.
  bool climateEnabled;

  /// v61 — set when this place is a Location inside another world
  /// (docs/design/locations-within-worlds.md). Null = root; every world was a
  /// root before the column existed. Climate, prose and lore resolve by
  /// walking parents through [WorldRepository.chainFor]; the repository
  /// refuses unknown parents and cycles at save time.
  String? parentWorldId;

  /// Convenience for UI and facade code: a world with a parent is a place
  /// inside one, everything else is a root.
  bool get isLocation => parentWorldId != null;

  /// Raw place-traits map (one future-proof field: unknown keys survive a
  /// round-trip so older apps never strip newer traits — mixed-fleet rule).
  /// Read through the typed getters; write through the setters.
  Map<String, dynamic> placeTraits;

  WorldAtmosphere get atmosphere =>
      worldAtmosphereFromName(placeTraits['atmosphere']?.toString());
  set atmosphere(WorldAtmosphere v) => v == WorldAtmosphere.breathable
      ? placeTraits.remove('atmosphere')
      : placeTraits['atmosphere'] = v.name;

  WorldGravity get gravity =>
      worldGravityFromName(placeTraits['gravity']?.toString());
  set gravity(WorldGravity v) => v == WorldGravity.earth
      ? placeTraits.remove('gravity')
      : placeTraits['gravity'] = v.name;

  /// Provenance marker for places the model minted from narration
  /// (locations slice 7 writes it; the library's model-made filter and
  /// bulk delete read it from slice 3 on). Rides the flexible
  /// [placeTraits] map so it never needs a migration and survives
  /// round-trips in newer builds.
  bool get isModelMade => placeTraits['madeBy']?.toString() == 'model';

  /// The place inside this world where a chat starts when the world is
  /// attached as its Setting (the star in the Worlds library). Null = chats
  /// start in the world itself. Rides [placeTraits] like [isModelMade], so
  /// it needs no migration and a climate-off world keeps it. Read it through
  /// `startingPlaceOf`, which ignores an id that no longer names a place
  /// inside this world, so a move or delete never needs a cleanup pass.
  String? get defaultPlaceId {
    final id = placeTraits['defaultPlace']?.toString() ?? '';
    return id.isEmpty ? null : id;
  }

  set defaultPlaceId(String? id) {
    if (id == null || id.isEmpty) {
      placeTraits.remove('defaultPlace');
    } else {
      placeTraits['defaultPlace'] = id;
    }
  }

  /// The character this world was built from (World from Character), or
  /// null. Provenance only: nothing is linked, so renaming or deleting the
  /// character leaves the world alone.
  String? get sourceCharacterName {
    final source = placeTraits['source'];
    if (source is! Map || source['kind'] != 'character') return null;
    final name = source['name']?.toString().trim() ?? '';
    return name.isEmpty ? null : name;
  }

  World({
    String? id,
    required this.name,
    this.description = '',
    required this.lorebook,
    this.biomeId,
    this.biomeJson,
    this.coverImage,
    this.sourceId,
    this.formatVersion = 1,
    this.linkedCharacterName,
    this.linkedCharacterId,
    this.avatarPath,
    this.injectDescription = true,
    this.climateEnabled = true,
    this.parentWorldId,
    Map<String, dynamic>? placeTraits,
  }) : id = id ?? const Uuid().v4(),
       placeTraits = placeTraits ?? {};

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'lorebook': lorebook.toJson(),
      if (climateEnabled && biomeId != null) 'biome_id': biomeId,
      if (climateEnabled && biomeJson != null) 'biome_json': biomeJson,
      if (coverImage != null) 'cover_image': coverImage,
      if (sourceId != null) 'source_id': sourceId,
      'format_version': formatVersion,
      if (linkedCharacterName != null)
        'linked_character_name': linkedCharacterName,
      if (linkedCharacterId != null) 'linked_character_id': linkedCharacterId,
      if (avatarPath != null) 'avatar_path': avatarPath,
      'inject_description': injectDescription,
      'climate_enabled': climateEnabled,
      if (parentWorldId != null) 'parent_world_id': parentWorldId,
      if (defaultPlaceId != null) 'default_place_id': defaultPlaceId,
      if (climateEnabled && placeTraits.isNotEmpty) 'place_traits': placeTraits,
    };
  }

  factory World.fromJson(Map<String, dynamic> json) {
    final String name = json['name']?.toString() ?? 'Imported World';
    final String description = json['description']?.toString() ?? '';
    final climateEnabled = readWorldClimateEnabled(json) ?? true;

    Lorebook lorebook;
    if (json['lorebook'] != null) {
      lorebook = Lorebook.fromJson(
        Map<String, dynamic>.from(json['lorebook'] as Map),
      );
    } else {
      lorebook = Lorebook.fromJson(json);
    }

    final world = World(
      id: json['id']?.toString(),
      name: name,
      description: description,
      lorebook: lorebook,
      biomeId: climateEnabled
          ? json['biome_id']?.toString() ?? json['biomeId']?.toString()
          : null,
      biomeJson: climateEnabled
          ? json['biome_json'] is String
                ? json['biome_json'] as String
                : (json['biome_json'] is Map
                      ? jsonEncode(json['biome_json'])
                      : null)
          : null,
      coverImage: json['cover_image']?.toString() ?? json['cover']?.toString(),
      sourceId: json['source_id']?.toString() ?? json['sourceId']?.toString(),
      formatVersion:
          (json['format_version'] as num?)?.toInt() ??
          (json['formatVersion'] as num?)?.toInt() ??
          1,
      linkedCharacterName: json['linked_character_name']?.toString(),
      linkedCharacterId: json['linked_character_id']?.toString(),
      avatarPath: json['avatar_path']?.toString(),
      injectDescription:
          json['inject_description'] as bool? ??
          json['injectDescription'] as bool? ??
          true,
      climateEnabled: climateEnabled,
      parentWorldId:
          json['parent_world_id']?.toString() ??
          json['parentWorldId']?.toString(),
      placeTraits: climateEnabled
          ? json['place_traits'] is Map
                ? Map<String, dynamic>.from(json['place_traits'] as Map)
                : json['placeTraits'] is Map
                ? Map<String, dynamic>.from(json['placeTraits'] as Map)
                : null
          : null,
    );
    // Top-level key wins over a copy inside place_traits, and survives a
    // climate-off world, whose place_traits are dropped above.
    final star =
        json['default_place_id']?.toString() ??
        json['defaultPlaceId']?.toString();
    if (star != null) world.defaultPlaceId = star;
    return world;
  }
}

/// Legacy flat-list climate gate. Prefer [primaryWorldAllowsClimate]:
/// Primary empty ⇒ weather OFF even when lore climate-on places are attached.
///
/// Kept for older call sites/tests that still pass an unordered attach list.
/// Empty list now returns false (was true / temperate fallback).
bool attachedWorldsAllowClimate(Iterable<World> worlds) {
  for (final w in worlds) {
    if (w.climateEnabled) return true;
  }
  return false;
}
