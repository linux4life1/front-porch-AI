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
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.locations.dart';

/// The chat-scene surface of the world relay (twin of [WorldLocationsRelay]
/// for the "where are we, what's the weather" panel): the places the active
/// chat has selected, the reach set behind the "Move the scene" dropdown,
/// and the mid-chat climate switch. All three answer through the SAME laws
/// the desktop panels and the save path lean on, so a phone can never be
/// shown a place or a climate the relay would refuse. Extracted from
/// WorldFacade; the facade forwards, keeping the route surface identical.
class WorldChatPlacesRelay {
  WorldChatPlacesRelay(this.worlds, this._chat, this.locations);

  final WorldRepository worlds;
  final ChatService? _chat;
  final WorldLocationsRelay locations;

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
            : worlds.resolveWorld(parentId)?.name,
      };
    }

    Map<String, dynamic>? primaryPlace;
    final primaryWorld = primaryId == null
        ? null
        : worlds.resolveWorld(primaryId);
    if (primaryWorld != null) {
      primaryPlace = placeJson(primaryWorld, role: 'primary');
    }

    final lorePlaces = <Map<String, dynamic>>[];
    for (final id in loreIds) {
      final w = worlds.resolveWorld(id);
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
        : worlds.climateAuthorFor(primaryId);
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
          : weatherOffRootOf(worlds.chainFor(primaryId))?.name,
      'reachable': locations.reachable(primaryId),
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
      final w = worlds.resolveWorld(ref);
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
        : worlds.climateAuthorFor(primaryId);
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
      final w = worlds.resolveWorld(biomeId.substring(6));
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
}
