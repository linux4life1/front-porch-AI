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

    return World(
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
      placeTraits: climateEnabled
          ? json['place_traits'] is Map
                ? Map<String, dynamic>.from(json['place_traits'] as Map)
                : json['placeTraits'] is Map
                ? Map<String, dynamic>.from(json['placeTraits'] as Map)
                : null
          : null,
    );
  }
}

/// Whether weather/climate should run for a chat given its attached worlds.
///
/// - No attached worlds → true (legacy temperate default still runs).
/// - Any attached world with [World.climateEnabled] → true.
/// - Every attached world has climate off → false (lorebook-only bookshelf).
bool attachedWorldsAllowClimate(Iterable<World> worlds) {
  var sawAny = false;
  for (final w in worlds) {
    sawAny = true;
    if (w.climateEnabled) return true;
  }
  return !sawAny;
}
