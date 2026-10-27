// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure Location-chain resolution (docs/design/locations-within-worlds.md §3).
// No DB, no Flutter: the repository feeds worlds in, gets an ordered chain,
// a climate author, or a save verdict back. The engine walks any chain; the
// two-level depth cap is editor policy, not a law of this file.

import 'package:front_porch_ai/models/world.dart';

/// What saving a location whose parent cannot be found reports.
const kWorldParentUnknown = 'That parent place no longer exists.';

/// What saving a place inside one of its own rooms reports.
const kWorldParentCycle = 'A place cannot live inside one of its own rooms.';

/// Ancestor chain leaf-first: `[S, parent(S), …, root]`.
///
/// Stops at a null parent, a lookup miss (a parent row deleted behind this
/// one, e.g. while a re-root is still in flight), and a repeat visit — a
/// ring left by a direct DB edit must never spin the walker. Deduped by id,
/// so the result is finite on any input.
List<World> worldChain(World leaf, World? Function(String id) lookup) {
  final chain = <World>[leaf];
  final seen = <String>{leaf.id};
  var cursor = leaf.parentWorldId;
  while (cursor != null && cursor.isNotEmpty && seen.add(cursor)) {
    final next = lookup(cursor);
    if (next == null) break;
    chain.add(next);
    cursor = next.parentWorldId;
  }
  return chain;
}

/// The first climate-enabled world in a [worldChain] — the place whose
/// biome, weather and traits the leaf reads. Null when the whole chain is
/// lore-only, and null when the root has weather off: a top-level world's
/// switch covers every place inside it, so a place that owns a climate
/// under a weather-off world keeps it saved but paused.
World? climateAuthorOf(List<World> chain) {
  if (chain.isEmpty || !chain.last.climateEnabled) return null;
  for (final w in chain) {
    if (w.climateEnabled) return w;
  }
  return null;
}

/// A chat's weather runs only when its Setting chain has a climate author.
/// For a root alone this is exactly the old `primaryWorldAllowsClimate`
/// answer — the gate just widened from "the Primary" to "the chain".
bool chainAllowsClimate(List<World> chain) => climateAuthorOf(chain) != null;

/// The top-level world of a place whose weather that world switched off,
/// or null for a root (its own switch says it) or a weather-on world.
World? weatherOffRootOf(List<World> chain) =>
    chain.length > 1 && !chain.last.climateEnabled ? chain.last : null;

/// Worlds the editor may offer as the parent of [self] (null = a create):
/// every root and every depth-1 world, minus [self] and minus its own
/// descendants — attaching one of those would ring the chain. Depth is
/// counted in places below a root (town → building → room is the cap;
/// docs/design/locations-within-worlds.md §3), and the cap is UI policy,
/// so it lives here rather than in the save path.
List<World> parentPickCandidates(
  World? self,
  List<World> all,
  World? Function(String id) lookup,
) {
  bool tooDeepOrCycled(World candidate) {
    if (self != null) {
      // A descendant of self (or self itself) would close a ring.
      final chain = worldChain(candidate, lookup);
      if (chain.any((w) => w.id == self.id)) return true;
    }
    // Depth after the move: candidate's depth must leave room for self's
    // subtree under the two-level cap.
    final candidateDepth = worldChain(candidate, lookup).length - 1;
    final selfHeight = self == null
        ? 1
        : _subtreeHeight(self, all, lookup, <String>{});
    return candidateDepth + selfHeight > 2;
  }

  return [
    for (final w in all)
      if (w.id != self?.id && !tooDeepOrCycled(w)) w,
  ];
}

/// Longest leaf-first chain below (and including) [world] — 1 for a world
/// with no children. [path] carries the ids on the current descent, undone
/// on the way back up so siblings still measure: a hand-edited ring
/// (A→B→A in the DB) would otherwise make the child walk spin until the
/// stack dies, exactly the case [worldChain] promises never to spin.
int _subtreeHeight(
  World world,
  List<World> all,
  World? Function(String id) lookup,
  Set<String> path,
) {
  if (!path.add(world.id)) return 1; // ring: stop, count this node only.
  final children = all.where((w) {
    final p = w.parentWorldId;
    return p != null && p.isNotEmpty && lookup(p)?.id == world.id;
  }).toList();
  final height = children.isEmpty
      ? 1
      : 1 +
            children
                .map((c) => _subtreeHeight(c, all, lookup, path))
                .reduce((a, b) => a > b ? a : b);
  path.remove(world.id);
  return height;
}

/// Places a chat may move to in one step from the current Setting: the
/// Setting itself, its parent, its siblings, and its children — everything
/// the breadcrumb dropdown offers (design §5). Unrelated worlds stay behind
/// the attach picker.
List<World> reachablePlaces(
  World setting,
  List<World> all,
  World? Function(String id) lookup,
) {
  final parent = setting.parentWorldId;
  final resolvedParent = (parent == null || parent.isEmpty)
      ? null
      : lookup(parent);
  // Dedupe by id: a self-parented row (direct DB edit) would otherwise
  // list the Setting twice, and the children/sibling loops coincide when
  // the parent resolves to the setting itself.
  final seen = <String>{setting.id};
  bool isUnder(World w, World p) =>
      w.id != setting.id &&
      w.parentWorldId != null &&
      lookup(w.parentWorldId!)?.id == p.id;
  return [
    setting,
    if (resolvedParent != null && seen.add(resolvedParent.id)) resolvedParent,
    for (final w in all)
      if (isUnder(w, setting) && seen.add(w.id)) w, // children
    if (resolvedParent != null)
      for (final w in all)
        if (isUnder(w, resolvedParent) && seen.add(w.id)) w, // siblings
  ];
}

/// Why saving [worldId] with parent [parentId] must be refused, or null
/// when it is legal. [parents] is every known id → parent id, straight from
/// the database — the cache can still be loading.
///
/// Unknown parents are refused: silently dropping one would quietly detach
/// somebody's rooms. A cycle is refused: a parent may not be the world
/// itself or any descendant of it. A ring further upstream that does not
/// pass through [worldId] is not this save's sin and does not block it.
String? parentRejection({
  required String worldId,
  required String? parentId,
  required Map<String, String?> parents,
}) {
  if (parentId == null || parentId.isEmpty) return null;
  if (!parents.containsKey(parentId)) return kWorldParentUnknown;
  if (parentId == worldId) return kWorldParentCycle;
  var cursor = parents[parentId];
  final visited = <String>{parentId};
  while (cursor != null && cursor.isNotEmpty && visited.add(cursor)) {
    if (cursor == worldId) return kWorldParentCycle;
    cursor = parents[cursor];
  }
  return null;
}

/// The places under [rootId] that own a climate — the ones a weather-off
/// switch on that world pauses. Walks each place's chain, so a room two
/// levels down counts too.
List<World> climateOwnersInside(
  String rootId,
  Iterable<World> all,
  World? Function(String id) lookup,
) => [
  for (final w in all)
    if (w.id != rootId &&
        w.climateEnabled &&
        w.parentWorldId != null &&
        worldChain(w, lookup).last.id == rootId)
      w,
];

/// What starring a place that is not inside the world reports.
const kWorldDefaultPlaceOutside = 'That place is not inside this world.';

/// True when [place] sits somewhere below [world] (any depth). A world is
/// not inside itself.
bool isPlaceInside(
  World place,
  World world,
  World? Function(String id) lookup,
) =>
    place.id != world.id &&
    worldChain(place, lookup).skip(1).any((w) => w.id == world.id);

/// The place a chat starts in when [world] is attached as its Setting: the
/// starred [World.defaultPlaceId] while it still names a place inside
/// [world], else [world] itself. A star left behind by a move out of the
/// tree or a delete resolves to the world, never to a stranger.
World startingPlaceOf(World world, World? Function(String id) lookup) {
  final id = world.defaultPlaceId;
  final place = id == null ? null : lookup(id);
  return place != null && isPlaceInside(place, world, lookup) ? place : world;
}

/// A bulk delete of [doomed]. A world's delete takes its whole tree, so only
/// [roots] (doomed rows with no doomed ancestor) are deleted; deleting a
/// child after its parent would hit a row that is already gone.
/// [alsoInside] counts the places outside [doomed] that go with them, so
/// the confirm can say how much hand-made work is lost.
({List<World> roots, int alsoInside}) bulkDeletePlan(
  List<World> doomed,
  Iterable<World> all,
  World? Function(String id) lookup,
) {
  final ids = {for (final d in doomed) d.id};
  final roots = [
    for (final d in doomed)
      if (!doomed.any((o) => isPlaceInside(d, o, lookup))) d,
  ];
  final alsoInside = all
      .where(
        (w) =>
            !ids.contains(w.id) &&
            roots.any((r) => isPlaceInside(w, r, lookup)),
      )
      .length;
  return (roots: roots, alsoInside: alsoInside);
}
