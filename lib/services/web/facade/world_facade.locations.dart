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
import 'package:front_porch_ai/services/world_chain.dart';

/// The locations-tree surface of the web relay (slice 4, twin of slice 3's
/// desktop UI): candidate lists and reach sets the PWA renders but must
/// not re-decide. Both answer through the SAME pure law the desktop pickers
/// and the repository save path lean on (`world_chain.dart`), so a phone
/// can never be shown a move the save would refuse.
class WorldLocationsRelay {
  WorldLocationsRelay(this._worlds);

  final WorldRepository _worlds;

  /// Worlds the PWA's "Part of" picker may offer. `forNameOrId` empty =
  /// a create. Depth caps and cycle exclusion come from
  /// [parentPickCandidates]; the client only formats labels.
  List<Map<String, dynamic>> parentCandidates(String forNameOrId) {
    final self = forNameOrId.isEmpty ? null : _worlds.resolveWorld(forNameOrId);
    return [
      for (final c in parentPickCandidates(
        self,
        _worlds.placeWorlds,
        _worlds.worldById,
      ))
        {
          'id': c.id,
          'name': c.name,
          // Depth-2 candidates render "X · inside Y" on the web exactly
          // as on desktop; the client resolves the label from this id.
          'parentWorldId': c.parentWorldId,
        },
    ];
  }

  /// One-step scene moves from [primaryId] (the "Move the scene"
  /// dropdown of the chat Places panel): self, parent, children,
  /// siblings per [reachablePlaces]. Empty when there is no setting or
  /// it no longer resolves.
  List<Map<String, dynamic>> reachable(String? primaryId) {
    final setting = (primaryId == null || primaryId.isEmpty)
        ? null
        : _worlds.resolveWorld(primaryId);
    if (setting == null) return const [];
    return [
      for (final r in reachablePlaces(
        setting,
        _worlds.placeWorlds,
        _worlds.worldById,
      ))
        {'id': r.id, 'name': r.name},
    ];
  }

  /// Direct children of [id] — the "N places" chip count. Direct only,
  /// per the desktop card law (grandchildren belong to their own chip).
  int locationCount(String id) =>
      _worlds.placeWorlds.where((c) => c.parentWorldId == id).length;

  /// The place whose climate this one reads (self if it authors, the
  /// nearest enabled ancestor if it inherits, null on a lore-only
  /// chain). Same walk the chat clock uses — the UI never re-decides.
  String? climateAuthorId(String id) => _worlds.climateAuthorFor(id)?.id;

  /// The starred place chats attached to [id] start in, or null when they
  /// start in the world itself (nothing starred, or the star went stale).
  /// Resolved here so the PWA's attach picker never re-decides it.
  String? startingPlaceId(String id) {
    final start = _worlds.startingPlaceFor(id);
    return start == null || start.id == id ? null : start.id;
  }

  /// Star [placeRef] as where chats attached to [worldRef] start; null or
  /// empty clears it. False when the world is unknown. The repository's
  /// refusal (a place outside the world) escapes as its StateError.
  Future<bool> setDefaultPlace(String worldRef, String? placeRef) async {
    final world = _worlds.resolveWorld(worldRef);
    if (world == null) return false;
    final place = (placeRef == null || placeRef.isEmpty)
        ? null
        : _worlds.resolveWorld(placeRef);
    if (placeRef != null && placeRef.isNotEmpty && place == null) {
      throw StateError(kWorldDefaultPlaceOutside);
    }
    await _worlds.setDefaultPlace(world, place?.id);
    return true;
  }
}

/// Review #596 cache honesty, extracted so the facade stays a coordinator:
/// the `World` the relay mutates IS the repository cache's instance, so
/// every field a requested save touches must come back out together when
/// the write fails or the law refuses. Take a snapshot BEFORE mutating
/// ([WorldSaveSnapshot.take]) and [restore] on any refusal — restoring
/// only the parent left ghost descriptions and lore on a refused move.
class WorldSaveSnapshot {
  WorldSaveSnapshot._(this._world, this._prior);

  factory WorldSaveSnapshot.take(World world) => WorldSaveSnapshot._(world, (
    description: world.description,
    climateEnabled: world.climateEnabled,
    biomeId: world.biomeId,
    biomeJson: world.biomeJson,
    injectDescription: world.injectDescription,
    parentWorldId: world.parentWorldId,
    coverImage: world.coverImage,
    atmosphere: world.atmosphere,
    gravity: world.gravity,
    lorebook: world.lorebook,
  ));

  final World _world;
  final ({
    String description,
    bool climateEnabled,
    String? biomeId,
    String? biomeJson,
    bool injectDescription,
    String? parentWorldId,
    String? coverImage,
    WorldAtmosphere atmosphere,
    WorldGravity gravity,
    Lorebook lorebook,
  })
  _prior;

  void restore() {
    _world.description = _prior.description;
    _world.climateEnabled = _prior.climateEnabled;
    _world.biomeId = _prior.biomeId;
    _world.biomeJson = _prior.biomeJson;
    _world.injectDescription = _prior.injectDescription;
    _world.parentWorldId = _prior.parentWorldId;
    _world.coverImage = _prior.coverImage;
    _world.atmosphere = _prior.atmosphere;
    _world.gravity = _prior.gravity;
    _world.lorebook = _prior.lorebook;
  }
}
