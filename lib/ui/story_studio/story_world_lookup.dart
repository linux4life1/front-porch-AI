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

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// What the story screens say about a story's world
/// (docs/design/stories-in-worlds.md §5). The words come from
/// [StoryWorldSummary], which the relay serves to the PWA too, so both
/// surfaces agree. Everything here reads the library live and degrades to
/// the stored name when the library is not there: the story pages are also
/// pumped in tests and goldens that have no world repository, and a world
/// line is never a reason for one to fail.

/// The world library, or null where none is provided.
WorldRepository? worldsOrNull(BuildContext context) {
  try {
    return Provider.of<WorldRepository>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// The live brief for [p]'s world; null without a world, empty when the
/// library has lost it.
StoryWorldBrief? storyWorldBrief(StoryProject p, WorldRepository? worlds) {
  final id = p.worldId;
  if (id == null || id.isEmpty || worlds == null) return null;
  return worldBriefFrom(worlds, id);
}

/// "Set in Greenhollow Estate · starts at The Conservatory", or the stored
/// name alone when the library cannot be asked, or a note that the world is
/// gone. Null for a story with no world.
String? storyWorldLine(StoryProject p, WorldRepository? worlds) {
  final id = p.worldId;
  if (id == null || id.isEmpty) return null;
  final brief = storyWorldBrief(p, worlds);
  final name = p.worldName.trim().isEmpty ? 'a world' : p.worldName.trim();
  if (brief == null) return 'Set in $name';
  if (brief.isEmpty) {
    return worlds!.isLoading
        ? 'Set in $name'
        : 'Set in $name (no longer in the library)';
  }
  return StoryWorldSummary.of(brief).setInLine;
}

/// The Engine step's line: what the brief carries and what the writer
/// searches.
String storyWorldBriefLine(StoryWorldBrief brief) =>
    StoryWorldSummary.of(brief).briefLine;

/// A scene the planner set somewhere the world does not have: the story
/// has a world, the scene has a location, and no place id resolved.
bool storySceneIsNewPlace(StoryProject p, StoryScene s) =>
    (p.worldId?.isNotEmpty ?? false) &&
    s.placeId.isEmpty &&
    s.location.trim().isNotEmpty;

/// What the New Story wizard keeps once a world is picked: where the story
/// starts, the world's name for the shelf, and a line for the card.
class StoryWorldPick {
  const StoryWorldPick({
    required this.placeId,
    required this.worldName,
    required this.detail,
    this.fromChat = false,
  });

  /// The place the story starts at (a chat's Setting would hold the same).
  final String placeId;

  /// The top-level world's name.
  final String worldName;

  /// "starts at The Conservatory · 3 places · 11 facts · Mediterranean".
  final String detail;

  /// Filled from the chat the story starts from, not picked by hand.
  final bool fromChat;
}

/// The pick for [chosen]: a root starts at its starred place, a place inside
/// a world starts there. Null when the library has no such world.
StoryWorldPick? storyWorldPickFor(
  World chosen,
  WorldRepository worlds, {
  bool fromChat = false,
}) {
  final start = chosen.isLocation
      ? chosen
      : startingPlaceOf(chosen, worlds.worldById);
  final brief = worldBriefFrom(worlds, start.id);
  if (brief.isEmpty) return null;
  final summary = StoryWorldSummary.of(brief);
  return StoryWorldPick(
    placeId: summary.placeId,
    worldName: summary.worldName,
    detail: summary.detail(brief),
    fromChat: fromChat,
  );
}

/// The pick a saved story resolves to when its setup is reopened.
StoryWorldPick? storyWorldPickFromProject(
  StoryProject p,
  WorldRepository? worlds,
) {
  final id = p.worldId;
  if (id == null || id.isEmpty) return null;
  final place = worlds?.worldById(id);
  if (place == null || worlds == null) {
    return StoryWorldPick(
      placeId: id,
      worldName: p.worldName,
      detail: worlds == null || worlds.isLoading
          ? ''
          : 'no longer in the library',
    );
  }
  return storyWorldPickFor(place, worlds);
}
