// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Saving a world together with its starting place: the place inside it
// where chats attached to the world begin. A world made by hand or by a
// world creator must name one; the New World dialog, the web editor and
// the World from Wiki / Character mint all save through here, so the rule
// for "create the place, star it, never leave a half" lives once.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// What a new world with no starting place reports.
const kWorldStartingPlaceRequired =
    'Name the place where chats in this world start.';

/// What a world whose places none is chosen as the start reports.
const kWorldStartingPlacePick =
    'Pick the place where chats in this world start.';

/// Where a world's chats start, as an editor or creator chose it: one of
/// its places, or a new place to create inside it.
sealed class StartingPlaceChoice {
  const StartingPlaceChoice();
}

/// Start at a place already inside the world.
class StartAtExistingPlace extends StartingPlaceChoice {
  const StartAtExistingPlace(this.placeId);
  final String placeId;
}

/// Create a place inside the world and start there. A blank [name] is no
/// choice at all; [description] becomes the place's prose.
class StartAtNewPlace extends StartingPlaceChoice {
  const StartAtNewPlace(this.name, {this.description = ''});
  final String name;
  final String description;
}

/// The refusal for saving a top-level world with [choice], or null when it
/// may be saved. [isNew] is a create; [hasPlaces] says whether the world
/// already holds places. A new world must name a place; an existing world
/// with places must pick one; an older world with none may stay as it is.
String? startingPlaceRejection(
  StartingPlaceChoice? choice, {
  required bool isNew,
  required bool hasPlaces,
}) {
  final named = switch (choice) {
    StartAtExistingPlace(:final placeId) => placeId.isNotEmpty,
    StartAtNewPlace(:final name) => name.trim().isNotEmpty,
    null => false,
  };
  if (named) return null;
  if (isNew) return kWorldStartingPlaceRequired;
  return hasPlaces ? kWorldStartingPlacePick : null;
}

/// Save [world] with its starting place. The star is written on [world]
/// before it is saved, so one save carries it; a new place is saved right
/// after, inside [world], inheriting its weather. When the place cannot be
/// saved a new [world] is deleted again (a world never exists without its
/// start) and an existing one gets its old star back. Returns the starting
/// place, or null when [choice] is null (an older world left as it was).
///
/// Refuses (StateError) an existing place that is not inside [world].
Future<model.World?> saveWorldWithStartingPlace(
  WorldRepository repo,
  model.World world,
  StartingPlaceChoice? choice, {
  required bool isNew,
}) async {
  final prior = world.defaultPlaceId;
  model.World? created;
  switch (choice) {
    case StartAtExistingPlace(:final placeId):
      final place = repo.worldById(placeId);
      if (place == null || !isPlaceInside(place, world, repo.worldById)) {
        throw StateError(kWorldDefaultPlaceOutside);
      }
      world.defaultPlaceId = placeId;
    case StartAtNewPlace(:final name, :final description):
      created = model.World(
        name: name.trim(),
        description: description.trim(),
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
        parentWorldId: world.id,
      );
      world.defaultPlaceId = created.id;
    case null:
      break;
  }
  try {
    await repo.saveWorld(world);
  } catch (_) {
    world.defaultPlaceId = prior;
    rethrow;
  }
  if (created == null) {
    return choice == null ? null : repo.worldById(world.defaultPlaceId!);
  }
  try {
    created.parentWorldId = world.id;
    await repo.saveWorld(created);
    return created;
  } catch (e) {
    try {
      if (isNew) {
        await repo.deleteWorld(world);
      } else {
        world.defaultPlaceId = prior;
        await repo.saveWorld(world);
      }
    } catch (undo) {
      debugPrint('starting place: could not undo the world save: $undo');
    }
    rethrow;
  }
}

/// Every place inside [world] (any depth), parents before their rooms —
/// what a starting-place picker offers.
List<model.World> placesInside(
  model.World world,
  List<model.World> all,
  model.World? Function(String id) lookup,
) => [
  for (final w in all)
    if (isPlaceInside(w, world, lookup)) w,
];
