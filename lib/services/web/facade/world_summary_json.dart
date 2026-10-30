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
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/web/facade/world_facade.locations.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

/// One row of the web relay's world list (`GET /api/worlds`). Fields are
/// additive only: older PWAs ignore what they do not know.
/// [linkedCharacterId] is resolved by the caller, which owns the
/// character-name index.
Map<String, dynamic> worldSummaryJson(
  World w, {
  required WorldLocationsRelay locations,
  String? linkedCharacterId,
}) => {
  'id': w.id,
  'name': w.name,
  'description': w.description,
  'entryCount': w.lorebook.entries.length,
  'enabledEntryCount': w.lorebook.enabledEntryCount,
  if (w.climateEnabled)
    'biomeId': (w.biomeJson != null && w.biomeJson!.isNotEmpty)
        ? 'custom'
        : (w.biomeId ?? 'temperate'),
  // Additive: the climate's own name, so a custom climate reads as the
  // desktop shows it (the group Setting picker's weather line).
  if (w.climateEnabled)
    'climateName': Biome.resolve(
      biomeId: w.biomeId,
      biomeJson: w.biomeJson,
    ).displayName,
  'injectDescription': w.injectDescription,
  'climateEnabled': w.climateEnabled,
  'coverImage': w.coverImage,
  'hasCover': w.coverImage != null && w.coverImage!.isNotEmpty,
  'linkedCharacterName': w.linkedCharacterName,
  'linkedCharacterId': linkedCharacterId,
  // Locations slice 4 (web twin): the PWA groups the library,
  // paints "inside X" tags and runs the model-made filter from
  // these. Additive — old builds ignore them (mixed-version law).
  'parentWorldId': w.parentWorldId,
  'isModelMade': w.isModelMade,
  // World from Character (additive): the "from <character>" tag.
  if (w.sourceCharacterName != null)
    'sourceCharacterName': w.sourceCharacterName,
  // Slice 5 (additive): "N places" chip and weather author for Stoop.
  'locationCount': locations.locationCount(w.id),
  'climateAuthorId': locations.climateAuthorId(w.id),
  // Additive: the starred place an attach-as-Setting lands on.
  'defaultPlaceId': locations.startingPlaceId(w.id),
};

/// The world editor's detail payload (`GET /api/worlds/<name>/detail`).
/// Additive only, like the list rows.
Map<String, dynamic> worldDetailJson(
  World w, {
  required WorldLocationsRelay locations,
}) => {
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
  // Additive: the editor's "Where chats start" picker preselects this.
  'defaultPlaceId': locations.startingPlaceId(w.id),
};
