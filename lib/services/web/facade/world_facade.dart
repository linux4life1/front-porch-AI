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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/models/lorebook_analysis.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';
import 'package:front_porch_ai/utils/utils.dart';

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
        {
          'id': w.id,
          'name': w.name,
          'description': w.description,
          'entryCount': w.lorebook.entries.length,
          if (w.climateEnabled)
            'biomeId': (w.biomeJson != null && w.biomeJson!.isNotEmpty)
                ? 'custom'
                : (w.biomeId ?? 'temperate'),
          'injectDescription': w.injectDescription,
          'climateEnabled': w.climateEnabled,
          'coverImage': w.coverImage,
          'hasCover': w.coverImage != null && w.coverImage!.isNotEmpty,
          'linkedCharacterName': w.linkedCharacterName,
          'linkedCharacterId':
              w.linkedCharacterId ??
              (w.linkedCharacterName != null
                  ? idByName[w.linkedCharacterName!]
                  : null),
        },
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
    existing ??= _worlds.worldByName(f['originalName']?.toString() ?? name);

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
        return false;
      }
    } else {
      world.name = name;
    }
    world.description = f['description']?.toString() ?? '';
    if (f.containsKey('climateEnabled')) {
      world.climateEnabled = f['climateEnabled'] == true;
    }
    // Lorebook-only worlds do not need a valid biome to save.
    if (world.climateEnabled && !_applyClimate(world, f)) return false;
    if (f.containsKey('injectDescription')) {
      world.injectDescription = f['injectDescription'] == true;
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
          buildLorebookFromJson(f['entries']) ?? Lorebook(entries: []);
    }
    await _worlds.saveWorld(world);
    return true;
  }

  Future<bool> delete(String nameOrId) async {
    final w = _worlds.resolveWorld(nameOrId);
    if (w == null) return false;
    await _worlds.deleteWorld(w);
    return true;
  }

  /// Import .fpworld or bare lorebook JSON as a place. Routes through
  /// WorldRepository.importWorldJson — the same path desktop file import
  /// uses — so climate, place traits, lore, provenance, and name
  /// uniquifying behave identically on both surfaces.
  Future<bool> importWorld(Map<String, dynamic> json) async {
    // Reject payloads that are neither a package envelope nor a lorebook.
    final isEnvelope =
        json.containsKey('formatVersion') ||
        (json.containsKey('id') &&
            json.containsKey('name') &&
            (json.containsKey('lorebook') || json.containsKey('lorebooks')));
    if (!isEnvelope &&
        json['entries'] == null &&
        json['lorebook'] == null &&
        detectLorebookFormat(json) == LorebookFormat.fpaiOrSt) {
      return false;
    }
    try {
      await _worlds.importWorldJson(json);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Import a lorebook with a chosen destination — the web twin of the
  /// desktop Import Lorebook wizard. `dryRun` returns the review summary +
  /// destination availability without writing anything; a commit clones the
  /// decoded entries into exactly one home. Additive API; the plain
  /// [importWorld] endpoint is untouched for older clients.
  Future<Map<String, dynamic>?> importLorebook(
    Map<String, dynamic> json, {
    bool dryRun = false,
    String destination = 'world',
    String? name,
    String? description,
    List<String> characterIds = const [],
  }) async {
    if (json['entries'] == null &&
        json['lorebook'] == null &&
        detectLorebookFormat(json) == LorebookFormat.fpaiOrSt) {
      return null; // unrecognized shape → 400
    }
    final source = json['lorebook'] is Map
        ? Map<String, dynamic>.from(json['lorebook'] as Map)
        : json;
    final book = Lorebook.fromJson(source);
    final summary = LorebookImportSummary.analyze(json, book);

    if (dryRun) {
      return {
        'format': summary.formatLabel,
        'suggestedName': summary.suggestedName,
        'suggestedDescription': summary.suggestedDescription,
        'entryCount': summary.entryCount,
        'enabledCount': summary.enabledCount,
        'approxTokens': summary.approxTokens,
        'features': summary.features,
        'warnings': summary.warnings,
        'canGroup': _chat?.activeGroup != null,
        'canChat': _chat?.currentSessionId != null,
      };
    }
    if (book.entries.isEmpty) return null;

    List<LorebookEntry> cloned() => [for (final e in book.entries) e.clone()];
    Lorebook clonedBook() => Lorebook(
      entries: cloned(),
      scanDepth: book.scanDepth,
      tokenBudget: book.tokenBudget,
      recursiveScanning: book.recursiveScanning,
      extensions: Map<String, dynamic>.from(book.extensions),
    );

    switch (destination) {
      case 'world':
        var base = (name ?? summary.suggestedName).trim();
        if (base.isEmpty) base = 'Imported Lorebook';
        final taken = _worlds.worlds.map((w) => w.name).toSet();
        var candidate = base;
        var i = 2;
        while (taken.contains(candidate)) {
          candidate = '$base ($i)';
          i++;
        }
        await _worlds.saveWorld(
          World(
            name: candidate,
            description: (description ?? summary.suggestedDescription).trim(),
            lorebook: clonedBook(),
          ),
        );
        return {'ok': true, 'where': 'world', 'name': candidate};
      case 'characters':
        final chars = _characters;
        if (chars == null || characterIds.isEmpty) return null;
        var count = 0;
        for (final c in chars.characters) {
          if (c.dbId == null || !characterIds.contains(c.dbId)) continue;
          final existing = c.lorebook;
          if (existing == null) {
            c.lorebook = clonedBook();
          } else {
            existing.entries.addAll(cloned());
          }
          await chars.updateCharacter(c);
          count++;
        }
        return count > 0
            ? {'ok': true, 'where': 'characters', 'count': count}
            : null;
      case 'group':
        final g = _chat?.activeGroup;
        final groups = _groups;
        if (g == null || groups == null) return null;
        final existing = g.groupLorebook.isEmpty
            ? Lorebook(entries: [])
            : Lorebook.fromJson(
                jsonDecode(g.groupLorebook) as Map<String, dynamic>,
              );
        existing.entries.addAll(cloned());
        g.groupLorebook = jsonEncode(existing.toJson());
        await groups.save(g);
        return {'ok': true, 'where': 'group', 'name': g.name};
      case 'chat':
        final chat = _chat;
        if (chat == null || chat.currentSessionId == null) return null;
        chat.chatLorebook.entries.addAll(cloned());
        await chat.commitChatLorebookEdit();
        return {'ok': true, 'where': 'chat'};
    }
    return null;
  }

  /// Export as .fpworld place package (lore + climate). Prefer over ST-only.
  Map<String, dynamic>? exportWorld(String nameOrId) {
    final w = _worlds.resolveWorld(nameOrId);
    if (w == null) return null;
    // Shared envelope core — same builder file export and Stoop upload use.
    return _worlds.fpWorldJson(w);
  }

  /// Legacy ST world-info export (lore only).
  Map<String, dynamic>? exportStWorld(String nameOrId) {
    final w = _worlds.resolveWorld(nameOrId);
    if (w == null) return null;
    return encodeStWorldInfo(
      w.lorebook,
      name: w.name,
      description: w.description,
    );
  }

  /// Chat session places (ids + names) + active climate for mid-chat override.
  Map<String, dynamic> chatPlaces() {
    final chat = _chat;
    if (chat == null || chat.currentSessionId == null) {
      return {
        'worldIds': <String>[],
        'places': <Map<String, dynamic>>[],
        'climateId': 'temperate',
        'climateDisplayName': Biome.temperate.displayName,
        'climateFeel': Biome.temperate.feel,
        'dayCount': 1,
      };
    }
    final ids = chat.chatWorldIds;
    final places = <Map<String, dynamic>>[];
    for (final id in ids) {
      final w = _worlds.resolveWorld(id);
      if (w == null) continue;
      places.add({
        'id': w.id,
        'name': w.name,
        // 'custom' is truthful for a place authoring its own climate —
        // reporting 'temperate' misled anything trusting this field.
        // Lorebook-only (climate-off) worlds omit biomeId entirely.
        if (w.climateEnabled)
          'biomeId': w.biomeJson != null
              ? 'custom'
              : (w.biomeId ?? 'temperate'),
        'hasCustomClimate': w.climateEnabled && w.biomeJson != null,
        'description': w.description,
      });
    }
    final climate = chat.activeChatBiome;
    return {
      'worldIds': ids,
      'places': places,
      'climateId': climate.id,
      'climateDisplayName': climate.displayName,
      'climateFeel': climate.feel,
      'dayCount': chat.timeService.dayCount,
      // Selectable climates for THIS chat: built-ins + any attached place
      // authoring its own ('world:<id>' scheme, shared with the desktop
      // panel). Additive — older bundles ignore it.
      'climateOptions': [
        for (final b in Biome.builtIns)
          {'id': b.id, 'displayName': b.displayName},
        for (final id in ids)
          if (_worlds.resolveWorld(id) case final w?)
            if (w.climateEnabled &&
                w.biomeJson != null &&
                Biome.tryParse(w.biomeJson) != null)
              {'id': 'world:${w.id}', 'displayName': '${w.name} (custom)'},
      ],
    };
  }

  Future<Map<String, dynamic>> setChatPlaces(List<String> worldIds) async {
    final chat = _chat;
    if (chat == null || chat.currentSessionId == null) {
      return {'ok': false, 'error': 'No active chat'};
    }
    // Resolve names → ids; only places.
    final resolved = <String>[];
    for (final ref in worldIds) {
      final w = _worlds.resolveWorld(ref);
      if (w == null || isCharacterLinkedWorld(w)) continue;
      if (!resolved.contains(w.id)) resolved.add(w.id);
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
    // Unknown ids error out rather than silently becoming temperate — a
    // typo'd climate must not look like a successful switch.
    Biome? biome = Biome.builtInById(biomeId);
    if (biome == null && biomeId.startsWith('world:')) {
      // An attached place's custom climate ('world:<id>', same scheme as
      // the desktop Places panel). Branded with the option id so the
      // active climate matches its picker option exactly on every surface.
      final w = _worlds.resolveWorld(biomeId.substring(6));
      if (w != null && chat.chatWorldIds.contains(w.id)) {
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
