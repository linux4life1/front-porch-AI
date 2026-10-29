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

import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/story/story_world_brief.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/world_store/world_starting_place.dart';

/// The story's world, read live from the library each time a stage or a
/// screen asks: the Setting chain of the picked place and every place
/// inside its root. Empty when the place is gone (a deleted world).
StoryWorldBrief worldBriefFrom(WorldRepository worlds, String worldId) {
  final chain = worlds.chainFor(worldId);
  if (chain.isEmpty) return StoryWorldBrief(chain: const [], places: const []);
  return StoryWorldBrief(
    chain: chain,
    places: placesInside(chain.last, worlds.worlds, worlds.worldById),
  );
}

/// What the screens say about a story's world, on the desktop and through
/// `/api/stories/world` for the PWA, so both read the same words
/// (docs/design/stories-in-worlds.md §5). Built from a brief, never from
/// the project, so a reopened story and a fresh pick agree.
class StoryWorldSummary {
  const StoryWorldSummary._({
    required this.placeId,
    required this.worldName,
    required this.startName,
    required this.atLarge,
    required this.placeCount,
    required this.factCount,
    required this.constantCount,
    required this.searchableCount,
    required this.climate,
    required this.places,
  });

  /// An empty brief: the world is gone, or none was picked.
  static const StoryWorldSummary none = StoryWorldSummary._(
    placeId: '',
    worldName: '',
    startName: '',
    atLarge: true,
    placeCount: 0,
    factCount: 0,
    constantCount: 0,
    searchableCount: 0,
    climate: null,
    places: [],
  );

  factory StoryWorldSummary.of(StoryWorldBrief brief) {
    final root = brief.root;
    final start = brief.start;
    if (root == null || start == null) return none;
    final author = climateAuthorOf(brief.chain);
    return StoryWorldSummary._(
      placeId: start.id,
      worldName: root.name.trim(),
      startName: start.name.trim(),
      atLarge: start.id == root.id,
      placeCount: brief.places.where((w) => w.id != root.id).length,
      factCount: brief.loreEntries().length,
      constantCount: brief.constantCount,
      searchableCount: brief.searchableCount,
      climate: author == null
          ? null
          : Biome.resolve(
              biomeId: author.biomeId,
              biomeJson: author.biomeJson,
            ).displayName,
      places: [
        for (final w in brief.places)
          if (w.id != root.id) (id: w.id, name: w.name.trim()),
      ],
    );
  }

  final String placeId;
  final String worldName;
  final String startName;
  final bool atLarge;
  final int placeCount;
  final int factCount;
  final int constantCount;
  final int searchableCount;
  final String? climate;
  final List<({String id, String name})> places;

  bool get isEmpty => placeId.isEmpty;

  /// "starts at The Conservatory" when the story starts at the world's
  /// starred place, "at The Kitchens" for another place, or the world at
  /// large. Decided by the world, not by what was clicked, so a reopened
  /// story reads the same.
  String whereLine(StoryWorldBrief brief) {
    if (atLarge) return 'the world at large';
    final root = brief.root!;
    final star = startingPlaceOf(root, (id) {
      if (id == root.id) return root;
      for (final w in brief.places) {
        if (w.id == id) return w;
      }
      return null;
    });
    return star.id == placeId ? 'starts at $startName' : 'at $startName';
  }

  /// The Idea card's detail: "starts at The Conservatory · 3 places · 11
  /// facts · Mediterranean".
  String detail(StoryWorldBrief brief) => [
    whereLine(brief),
    '$placeCount place${placeCount == 1 ? '' : 's'}',
    '$factCount fact${factCount == 1 ? '' : 's'}',
    ?climate,
  ].join(' · ');

  /// The Engine step's line.
  String get briefLine =>
      'World brief: $placeCount place${placeCount == 1 ? '' : 's'} · '
      '$constantCount always-on fact${constantCount == 1 ? '' : 's'} · '
      '$searchableCount searchable fact${searchableCount == 1 ? '' : 's'}';

  /// "Set in Greenhollow Estate · starts at The Conservatory".
  String get setInLine => atLarge
      ? 'Set in $worldName'
      : 'Set in $worldName · starts at $startName';

  /// The relay payload (additive; an older client ignores what it does not
  /// know).
  Map<String, dynamic> toJson(StoryWorldBrief brief) => {
    'ok': !isEmpty,
    'placeId': placeId,
    'worldName': worldName,
    'startName': startName,
    'atLarge': atLarge,
    'placeCount': placeCount,
    'factCount': factCount,
    'constantCount': constantCount,
    'searchableCount': searchableCount,
    'climate': climate,
    'detail': isEmpty ? '' : detail(brief),
    'briefLine': isEmpty ? '' : briefLine,
    'setInLine': isEmpty ? '' : setInLine,
    'places': [
      for (final p in places) {'id': p.id, 'name': p.name},
    ],
  };
}
