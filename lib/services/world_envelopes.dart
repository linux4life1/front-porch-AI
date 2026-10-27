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

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/models.dart' hide World;
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Slice 5: the envelope half of the locations feature, split out of
/// [WorldRepository] to keep both files under the 500-line ratchet and
/// because tree-shaping is its own job: which root an envelope carries
/// (its whole tree rides along) and how a `locations` array re-homes on
/// import. The repository stays the sole owner of persistence and the
/// save law; this class only reads the live cache and calls back through
/// the public repository surface, so there is still ONE source of truth
/// per law (design §2).
class WorldEnvelopeCodec {
  /// [totalCap] bounds how many location rows ONE import may create in
  /// total (review #599: a hand-edited or hostile envelope could carry
  /// thousands of children; each saveWorld is DB + cache + notify, so an
  /// unbounded loop is a UI freeze). Overridable for tests only.
  WorldEnvelopeCodec(this._repo, {int totalCap = kImportTotalCap})
    : _totalCap = totalCap;

  final WorldRepository _repo;
  final int _totalCap;

  /// Hard ceiling on location rows created by one import, any depth.
  /// Generous for real libraries; a runaway tree trips it and the rest
  /// is skipped with a log.
  static const int kImportTotalCap = 500;

  /// Levels of nesting the importer accepts below an imported root:
  /// town > building > room. This cap is EDITOR policy (as stated in
  /// world_chain.dart) — saveWorld itself enforces parent existence and
  /// cycles but not depth, so a DB edited outside the app can hold
  /// deeper chains; re-importing such a tree truncates it here rather
  /// than throwing at a caller whose root already landed.
  static const int kImportDepthCap = 2;

  /// Build the export envelope for [world]: always its ROOT's envelope
  /// with the whole tree. A place is never exported alone or as a pruned
  /// branch: that file read as the world, dropped its sibling places, and
  /// could lose the starting place on import.
  Map<String, dynamic> tree(model.World world) {
    final root = rootOf(world);
    return encodeFpWorld(
      world: root,
      biome: biomeFor(root),
      locations: subtreeEnvelopes(root),
    );
  }

  /// Re-home child envelopes from a `locations` array under [parentId].
  /// Structure decides parentage, never the sender's ids — each child
  /// gets a fresh local id and keeps its envelope id as `sourceId`
  /// (the root importer's provenance law, applied per level). A broken
  /// child is skipped, never fatal: the root already imported.
  ///
  /// [ids], when given, collects envelope id -> new local id for every
  /// place created, so the caller can re-point the root's starred place.
  Future<void> importLocations(
    List<Map<String, dynamic>> envelopes,
    String parentId,
    int depth, {
    Map<String, String>? ids,
  }) async {
    await _importWithBudget(envelopes, parentId, depth, _totalCap, ids);
  }

  Future<int> _importWithBudget(
    List<Map<String, dynamic>> envelopes,
    String parentId,
    int depth,
    int left,
    Map<String, String>? ids,
  ) async {
    if (envelopes.isEmpty) return left;
    if (depth > kImportDepthCap) {
      debugPrint(
        'world import: skipped ${envelopes.length} location(s) below '
        'the depth cap ($kImportDepthCap)',
      );
      return left;
    }
    const uuid = Uuid();
    for (var i = 0; i < envelopes.length; i++) {
      if (left <= 0) {
        debugPrint(
          'world import: skipped ${envelopes.length - i} location(s) at '
          'depth $depth past the total import cap ($_totalCap)',
        );
        // The skipped siblings' subtrees die with them: no partial limb.
        break;
      }
      final raw = envelopes[i];
      try {
        final pkg = decodeFpWorld(raw);
        final child = pkg.world;
        final envelopeId = child.id;
        child.sourceId ??= child.id.isNotEmpty ? child.id : null;
        child.id = uuid.v4();
        // A star inside this branch names a sender id; it is re-pointed
        // by the root import, never carried over raw.
        final senderStar = child.defaultPlaceId;
        child.defaultPlaceId = null;
        child.parentWorldId = parentId;
        child.name = uniqueWorldName(
          child.name,
          (n) => _repo.worlds.any((w) => w.name == n),
        );
        if (pkg.biome != null) {
          final biome = Biome.fromJson(pkg.biome!);
          child.biomeId = biome.id;
          child.biomeJson = Biome.builtInById(biome.id) != null
              ? null
              : biome.toJsonString();
        }
        await _repo.saveWorld(child);
        if (envelopeId.isNotEmpty) ids?[envelopeId] = child.id;
        left = await _importWithBudget(
          pkg.locations,
          child.id,
          depth + 1,
          left - 1,
          ids,
        );
        final star = senderStar == null ? null : ids?[senderStar];
        if (star != null) await _repo.setDefaultPlace(child, star);
      } catch (e) {
        // Names are user prose; log the frame, not the content.
        debugPrint('world import: skipped 1 location at depth $depth: $e');
      }
    }
    return left;
  }

  Map<String, dynamic>? biomeFor(model.World world) => world.climateEnabled
      ? Biome.resolve(
          biomeId: world.biomeId,
          biomeJson: world.biomeJson,
        ).toJson()
      : null;

  /// Walk parent ids to the root. Dangling or cyclic chains stop at the
  /// deepest resolvable place, which is then treated as the root — an
  /// export never loops, matching the planner's flat-dangling rule.
  model.World rootOf(model.World world) {
    var cur = world;
    final seen = <String>{cur.id};
    while (true) {
      final pid = cur.parentWorldId;
      if (pid == null) return cur;
      final parent = _repo.worldById(pid);
      if (parent == null || !seen.add(parent.id)) return cur;
      cur = parent;
    }
  }

  /// Full subtree as nested envelopes; the depth bound guards against
  /// corrupt parent chains, not policy — the save law caps the tree.
  List<Map<String, dynamic>> subtreeEnvelopes(
    model.World parent, {
    int depth = 1,
  }) {
    if (depth > 4) return const [];
    return [
      for (final child in _repo.placeWorlds.where(
        (w) => w.parentWorldId == parent.id,
      ))
        encodeFpWorld(
          world: child,
          biome: biomeFor(child),
          locations: subtreeEnvelopes(child, depth: depth + 1),
        ),
    ];
  }
}
