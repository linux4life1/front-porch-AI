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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.locations.dart';
import 'package:front_porch_ai/services/web/facade/world_summary_json.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.import.dart';

/// Thin adapter for world (portable place) CRUD over [WorldRepository].
/// Worlds have stable UUID identity; name is display-only.
///
/// The optional [_characters] repository lets [list] resolve a linked world's
/// character to its database id so the web UI can reuse the existing
/// `/api/characters/<id>/avatar` route for the world's portrait — no new image
/// endpoint and no client-supplied paths (best security posture).
class WorldFacade {
  WorldFacade(this._worlds, [this._characters, this._chat, this._groups]);

  final WorldRepository _worlds;
  final CharacterRepository? _characters;
  final ChatService? _chat;
  final GroupChatRepository? _groups;

  late final WorldImporter importer = WorldImporter(
    _worlds,
    _characters,
    _chat,
    _groups,
  );

  /// See [WorldImporter.importWorld].
  Future<bool> importWorld(Map<String, dynamic> json) =>
      importer.importWorld(json);

  /// See [WorldImporter.importLorebook].
  Future<Map<String, dynamic>?> importLorebook(
    Map<String, dynamic> json, {
    bool dryRun = false,
    String destination = 'world',
    String? name,
    String? description,
    List<String> characterIds = const [],
  }) => importer.importLorebook(
    json,
    dryRun: dryRun,
    destination: destination,
    name: name,
    description: description,
    characterIds: characterIds,
  );

  // Locations-tree relay surface: candidate law, reach set, starting place.
  late final WorldLocationsRelay locations = WorldLocationsRelay(_worlds);

  /// See [WorldLocationsRelay.parentCandidates].
  List<Map<String, dynamic>> parentCandidates(String forNameOrId) =>
      locations.parentCandidates(forNameOrId);

  /// See [WorldLocationsRelay.reachable].
  List<Map<String, dynamic>> reachable(String? primaryId) =>
      locations.reachable(primaryId);

  List<Map<String, dynamic>> list() {
    // Build a single name→dbId index so the per-world map below is O(1) and we
    // avoid a nested scan per world.
    final idByName = <String, String>{};
    final repo = _characters;
    if (repo != null) {
      for (final c in repo.characters) {
        final id = c.dbId;
        if (id != null) idByName.putIfAbsent(c.name, () => id);
      }
    }
    // Places only in the authoring list (character-linked clones purged).
    return [
      for (final w in _worlds.placeWorlds)
        worldSummaryJson(
          w,
          locations: locations,
          linkedCharacterId:
              w.linkedCharacterId ??
              (w.linkedCharacterName != null
                  ? idByName[w.linkedCharacterName!]
                  : null),
        ),
    ];
  }

  /// Built-in climates for the web editor (id, labels, feel copy).
  List<Map<String, dynamic>> climates() => [
    for (final b in Biome.builtIns)
      {
        'id': b.id,
        'displayName': b.displayName,
        'description': b.description,
        'feel': b.feel,
        'template': b.toJson(),
      },
  ];

  Map<String, dynamic>? detail(String nameOrId) {
    final w = _worlds.resolveWorld(nameOrId);
    if (w == null || isCharacterLinkedWorld(w)) return null;
    return {
      'id': w.id,
      'name': w.name,
      'description': w.description,
      if (w.climateEnabled)
        'biomeId': (w.biomeJson != null && w.biomeJson!.isNotEmpty)
            ? 'custom'
            : (w.biomeId ?? 'temperate'),
      if (w.climateEnabled) 'biome': Biome.tryParse(w.biomeJson)?.toJson(),
      'injectDescription': w.injectDescription,
      'climateEnabled': w.climateEnabled,
      'coverImage': w.coverImage,
      'linkedCharacterName': w.linkedCharacterName,
      'linkedCharacterId': w.linkedCharacterId,
      'entries': lorebookEntriesToJson(w.lorebook),
      if (w.climateEnabled) 'atmosphere': w.atmosphere.name,
      if (w.climateEnabled) 'gravity': w.gravity.name,
      // Slice 4 web twin: the editor preselects "Part of" and shows the
      // inherit-or-own radios from this. Additive.
      'parentWorldId': w.parentWorldId,
      // Slice 5 (additive): same keys as the list rows.
      'locationCount': locations.locationCount(w.id),
      'climateAuthorId': locations.climateAuthorId(w.id),
    };
  }

  /// Create or update a world by id when provided; rename is name-only.
  Future<bool> save(Map<String, dynamic> f) async {
    final name = f['name']?.toString().trim() ?? '';
    if (name.isEmpty) return false;
    final id = f['id']?.toString();
    World? existing;
    if (id != null && id.isNotEmpty) {
      existing = _worlds.worldById(id);
    }
    // `create: true` is a new place: a taken name gets "Name (2)" from
    // saveWorld, as on desktop, instead of overwriting the world that has
    // it. Without the flag a bare name still upserts.
    if (f['create'] != true) {
      existing ??= _worlds.worldByName(f['originalName']?.toString() ?? name);
    }

    final world =
        existing ??
        World(
          name: name,
          lorebook: Lorebook(entries: []),
        );
    if (existing != null && name != existing.name) {
      try {
        await _worlds.renameWorld(existing, name);
      } on StateError {
        // Review #596: report the collision, don't let the route guess.
        // renameWorld checks the DB before mutating, so nothing to roll
        // back here — but the cache name must not have moved.
        throw StateError('A world named "$name" already exists.');
      }
    } else {
      world.name = name;
    }
    // Review #596 cache honesty, whole-field edition: this World IS the
    // repository cache's instance. Every field written below must come
    // back out if the save fails or the law refuses — the snapshot/
    // restore pair lives in [WorldSaveSnapshot] so this file stays a
    // coordinator, not a second god file in the making.
    final snapshot = WorldSaveSnapshot.take(world);

    world.description = f['description']?.toString() ?? '';
    if (f.containsKey('climateEnabled')) {
      world.climateEnabled = f['climateEnabled'] == true;
    }
    // Lorebook-only worlds do not need a valid biome to save.
    if (world.climateEnabled && !_applyClimate(world, f)) {
      // Review #596: a bad climate throws its own sentence (was: false
      // -> the route's 'name is required' lie).
      snapshot.restore();
      throw StateError(
        'The custom climate is not valid — fix overlapping or missing '
        'season data.',
      );
    }
    if (f.containsKey('injectDescription')) {
      world.injectDescription = f['injectDescription'] == true;
    }
    // World from Character (additive): the PWA passes the root's
    // provenance from the wizard's done event. Absent keys keep what the
    // row has; the desktop stamps the same two fields.
    if (f.containsKey('sourceId')) {
      final sourceId = f['sourceId']?.toString().trim() ?? '';
      world.sourceId = sourceId.isEmpty ? null : sourceId;
    }
    if (f['placeTraits'] is Map) {
      world.placeTraits.addAll(
        Map<String, dynamic>.from(f['placeTraits'] as Map),
      );
    }
    // Slice 4 web twin: "Part of" changes the parent. Absent key keeps
    // the row's parent (same upsert discipline as the climate fields);
    // an explicit null or '' detaches it to its own world. The unknown/
    // cycle law still runs inside saveWorld and its StateError escapes
    // to the route, which answers 400 with the law's own sentence —
    // the PWA must never be able to persist what the desktop refuses.
    if (f.containsKey('parentWorldId')) {
      final parent = f['parentWorldId']?.toString().trim();
      world.parentWorldId = (parent == null || parent.isEmpty) ? null : parent;
    }
    if (f.containsKey('coverImage')) {
      final raw = f['coverImage']?.toString();
      world.coverImage = (raw == null || raw.isEmpty) ? null : raw;
    }
    if (world.climateEnabled) {
      if (f.containsKey('atmosphere')) {
        world.atmosphere = worldAtmosphereFromName(f['atmosphere']?.toString());
      }
      if (f.containsKey('gravity')) {
        world.gravity = worldGravityFromName(f['gravity']?.toString());
      }
    }
    if (f['entries'] != null) {
      world.lorebook =
          buildLorebookFromJson(f['entries'], bookFields: f) ??
          Lorebook(entries: []);
    }
    try {
      await _worlds.saveWorld(world);
    } catch (e) {
      // ANY failure — the law's StateError or a DB fault — restores the
      // complete prior state (desktop #592 discipline; the parent-only
      // rollback this replaces left every other field as a ghost).
      snapshot.restore();
      rethrow;
    }
    return true;
  }

  /// [onReRooted] reports how many children the delete turned into their
  /// own worlds (slice 4 web twin of desktop's re-root snack). Optional —
  /// callers that only care about success keep the bool contract.
  Future<bool> delete(
    String nameOrId, {
    void Function(int reRooted)? onReRooted,
  }) async {
    final w = _worlds.resolveWorld(nameOrId);
    if (w == null) return false;
    final moved = await _worlds.deleteWorld(w);
    onReRooted?.call(moved);
    return true;
  }

  /// Export as .fpworld place package (lore + climate). Prefer over ST-only.
  Map<String, dynamic>? exportWorld(String nameOrId) {
    final w = _worlds.resolveWorld(nameOrId);
    if (w == null) return null;
    // Shared envelope core — same builder file export and Stoop upload use.
    return _worlds.fpWorldJson(w);
  }

  /// Chat session places (ids + names) + active climate for mid-chat override.
  Map<String, dynamic> chatPlaces() {
    final chat = _chat;
    if (chat == null || chat.currentSessionId == null) {
      return {
        'worldIds': <String>[],
        'primaryId': null,
        'places': <Map<String, dynamic>>[],
        'lorePlaces': <Map<String, dynamic>>[],
        'climateAuthors': false,
        'climateAuthorName': null,
        'reachable': <Map<String, dynamic>>[],
        'weatherOff': 'no_setting',
        'climateId': 'temperate',
        'climateDisplayName': Biome.temperate.displayName,
        'climateFeel': Biome.temperate.feel,
        'dayCount': 1,
        'climateOptions': <Map<String, dynamic>>[],
      };
    }
    final primaryId = chat.chatPrimaryWorldId;
    final loreIds = chat.chatLoreWorldIds;
    final ids = chat.chatWorldIds;

    Map<String, dynamic> placeJson(World w, {required String role}) {
      final parentId = w.parentWorldId;
      return {
        'id': w.id,
        'name': w.name,
        'role': role,
        'climateEnabled': w.climateEnabled,
        if (w.climateEnabled)
          'biomeId': w.biomeJson != null
              ? 'custom'
              : (w.biomeId ?? 'temperate'),
        'hasCustomClimate': w.climateEnabled && w.biomeJson != null,
        'description': w.description,
        // Slice 4 web twin: "inside X" breadcrumbs on Setting and Lore
        // tiles read these (desktop cards' parity, mockup p3).
        'parentWorldId': parentId,
        'parentName': parentId == null || parentId.isEmpty
            ? null
            : _worlds.resolveWorld(parentId)?.name,
      };
    }

    Map<String, dynamic>? primaryPlace;
    final primaryWorld = primaryId == null
        ? null
        : _worlds.resolveWorld(primaryId);
    if (primaryWorld != null) {
      primaryPlace = placeJson(primaryWorld, role: 'primary');
    }

    final lorePlaces = <Map<String, dynamic>>[];
    for (final id in loreIds) {
      final w = _worlds.resolveWorld(id);
      if (w == null) continue;
      lorePlaces.add(placeJson(w, role: 'lore'));
    }

    // Older clients: flat places list (primary first, then lore).
    final places = <Map<String, dynamic>>[?primaryPlace, ...lorePlaces];

    // The Setting's chain author owns climate (locations slice 2) — the
    // same resolution the desktop weather gate uses. A location inherits;
    // the custom dropdown entry stays `world:<climate-author-id>`.
    final climateAuthor = primaryId == null
        ? null
        : _worlds.climateAuthorFor(primaryId);
    final climateAuthors = climateAuthor != null;
    final String? weatherOff = primaryId == null
        ? 'no_setting'
        : (!climateAuthors ? 'setting_lore_only' : null);

    final climate = chat.activeChatBiome;
    return {
      'worldIds': ids,
      'primaryId': primaryId,
      'primary': primaryPlace,
      'places': places,
      'lorePlaces': lorePlaces,
      'climateAuthors': climateAuthors,
      // Slice 4 web twin: the PWA names the weather author on an
      // inheriting Setting ("Weather from <name>", desktop parity) and
      // fills the "Move the scene" dropdown from the ONE Dart reach law
      // — no second TypeScript implementation of the rule.
      'climateAuthorName': climateAuthor?.name,
      // Additive: the top-level world whose weather-off switch silences
      // this Setting (weatherOff stays 'setting_lore_only' for old clients).
      'weatherOffWorldName': primaryId == null
          ? null
          : weatherOffRootOf(_worlds.chainFor(primaryId))?.name,
      'reachable': reachable(primaryId),
      'weatherOff': ?weatherOff,
      'climateId': climate.id,
      'climateDisplayName': climate.displayName,
      'climateFeel': climate.feel,
      'dayCount': chat.timeService.dayCount,
      // Built-ins + the climate AUTHOR's custom only (never lore climate-on).
      'climateOptions': [
        if (climateAuthors) ...[
          for (final b in Biome.builtIns)
            {'id': b.id, 'displayName': b.displayName},
          if (climateAuthor.biomeJson != null &&
              Biome.tryParse(climateAuthor.biomeJson) != null)
            {
              'id': 'world:${climateAuthor.id}',
              'displayName': '${climateAuthor.name} (custom)',
            },
        ],
      ],
    };
  }

  Future<Map<String, dynamic>> setChatPlaces(
    List<String> worldIds, {
    String? primaryId,
    List<String>? loreIds,
  }) async {
    final chat = _chat;
    if (chat == null || chat.currentSessionId == null) {
      return {'ok': false, 'error': 'No active chat'};
    }

    String? resolveRef(String ref) {
      final w = _worlds.resolveWorld(ref);
      if (w == null || isCharacterLinkedWorld(w)) return null;
      return w.id;
    }

    if (primaryId != null || loreIds != null) {
      final p = primaryId == null || primaryId.isEmpty
          ? null
          : resolveRef(primaryId);
      final lore = <String>[];
      for (final ref in loreIds ?? const <String>[]) {
        final id = resolveRef(ref);
        if (id != null && id != p && !lore.contains(id)) lore.add(id);
      }
      await chat.setChatPlaceSlots(primaryId: p, loreIds: lore);
      return {'ok': true, ...chatPlaces()};
    }

    // Legacy flat worldIds: preserve Primary if still listed; else all lore.
    final resolved = <String>[];
    for (final ref in worldIds) {
      final id = resolveRef(ref);
      if (id != null && !resolved.contains(id)) resolved.add(id);
    }
    await chat.setChatWorldIds(resolved);
    return {'ok': true, ...chatPlaces()};
  }

  /// Mid-chat climate switch from current story day (span snapshot).
  Future<Map<String, dynamic>> setChatClimate(String biomeId) async {
    final chat = _chat;
    if (chat == null || chat.currentSessionId == null) {
      return {'ok': false, 'error': 'No active chat'};
    }
    final primaryId = chat.chatPrimaryWorldId;
    // The chain author owns the switch (locations slice 2): a location
    // setting may change climate because its parent authors one.
    final author = primaryId == null
        ? null
        : _worlds.climateAuthorFor(primaryId);
    if (author == null) {
      return {
        'ok': false,
        'error': primaryId == null
            ? 'No setting — weather stays off'
            : 'This setting is lore-only — no weather',
      };
    }
    Biome? biome = Biome.builtInById(biomeId);
    if (biome == null && biomeId.startsWith('world:')) {
      // Custom climate only from the chain's climate author.
      final w = _worlds.resolveWorld(biomeId.substring(6));
      if (w != null && w.id == author.id) {
        biome = Biome.tryParse(w.biomeJson)?.withId('world:${w.id}');
      }
    }
    if (biome == null) {
      return {'ok': false, 'error': 'Unknown climate: $biomeId'};
    }
    await chat.setChatClimate(biome);
    return {'ok': true, ...chatPlaces()};
  }

  /// Server-side overlap / 2–8 check. Same [Biome.validate] as desktop save.
  List<String> climateErrors(Map<String, dynamic> json) {
    try {
      return Biome.fromJson(json).validate();
    } catch (_) {
      return const ['Could not read that climate'];
    }
  }

  bool _applyClimate(World world, Map<String, dynamic> f) {
    final custom = f['biomeId'] == 'custom' || f['biome'] is Map;
    if (!custom) {
      if (f.containsKey('biomeId')) {
        world.biomeId = f['biomeId']?.toString();
        world.biomeJson = null;
      }
      return true;
    }
    Map<String, dynamic>? map;
    final raw = f['biome'];
    if (raw is Map) map = Map<String, dynamic>.from(raw);
    final biome = map != null
        ? Biome.fromJson(map)
        : Biome.tryParse(f['biomeJson']?.toString());
    if (biome == null || biome.validate().isNotEmpty) return false;
    world.biomeId = null;
    world.biomeJson = biome.toJsonString();
    return true;
  }
}
