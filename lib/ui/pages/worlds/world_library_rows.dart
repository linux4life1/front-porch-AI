// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure row plan for the Worlds library with locations
// (docs/design/locations-within-worlds.md §5): only top-level worlds get
// cards; a world's places (its section's subtree) render as rows in the
// panel its card opens. No Flutter here — the page consumes
// [planWorldLibrary] and renders; the widget test pins the plan.

import 'package:front_porch_ai/models/world.dart';

enum WorldLibraryFilter { all, modelMade }

/// A root that has places inside it, rendered as its own section.
class WorldLibrarySection {
  final World root;
  final List<World> places;

  const WorldLibrarySection({required this.root, required this.places});
}

class WorldLibraryPlan {
  /// Sections: roots with children (subtree, DFS), in repo order.
  final List<WorldLibrarySection> sections;

  /// Flat grid cards: childless roots, dangling-parent cargo, and — only
  /// under [WorldLibraryFilter.modelMade] — model-made worlds at any depth.
  final List<World> flat;

  const WorldLibraryPlan({required this.sections, required this.flat});
}

/// A world is a location iff its parent id is set AND that parent resolves
/// in [all]. A dangling parent (deleted behind the re-root, hand-edited
/// library) must still be VISIBLE, so it counts as flat, not as a child.
bool _isLocation(World w, Map<String, World> byId) {
  final p = w.parentWorldId;
  return p != null && p.isNotEmpty && byId.containsKey(p);
}

/// Pure planning step. [worlds] arrives in library order (repo.placeWorlds);
/// a collapsed root keeps its section but reports its children hidden —
/// expansion is the caller's state, echoed back verbatim here.
WorldLibraryPlan planWorldLibrary({
  required List<World> worlds,
  required WorldLibraryFilter filter,
}) {
  final byId = {for (final w in worlds) w.id: w};
  final locations = worlds.where((w) => _isLocation(w, byId)).toList();
  final byParent = <String, List<World>>{};
  for (final w in locations) {
    byParent.putIfAbsent(w.parentWorldId!, () => []).add(w);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  if (filter == WorldLibraryFilter.modelMade) {
    return WorldLibraryPlan(
      sections: const [],
      flat: worlds.where((w) => w.isModelMade).toList(),
    );
  }

  final sections = <WorldLibrarySection>[];
  final flat = <World>[];
  for (final w in worlds) {
    if (_isLocation(w, byId)) continue; // children render inside sections
    final subtree = _subtreeOf(w.id, byParent);
    // The root itself always renders through its section when it has
    // children — never also in the flat grid (no duplicate cards).
    if (byParent.containsKey(w.id)) {
      sections.add(WorldLibrarySection(root: w, places: subtree));
    } else {
      flat.add(w);
    }
  }
  final placed = {
    for (final s in sections) s.root.id,
    for (final p in sections.expand((s) => s.places)) p.id,
  };
  return WorldLibraryPlan(
    sections: sections,
    // Ring members (a direct-DB ring the save path now refuses) are each
    // other's parents: `_isLocation` is true for all of them and no root
    // walk reaches them, so without this they vanish from the library
    // while still emitting lore. Show them flat, like dangling cargo.
    flat: [
      ...flat,
      for (final w in worlds)
        if (_isLocation(w, byId) && !placed.contains(w.id)) w,
    ],
  );
}

/// Every descendant of [rootId] in library order: each child followed
/// immediately by its own children (depth-first), so a room never appears
/// before the building that holds it.
List<World> _subtreeOf(String rootId, Map<String, List<World>> byParent) {
  final out = <World>[];
  void walk(String id) {
    for (final child in byParent[id] ?? const <World>[]) {
      out.add(child);
      walk(child.id);
    }
  }

  walk(rootId);
  return out;
}

/// Library display order for pickers: every root followed immediately by
/// its subtree (depth-first), dangling-parent locations last among
/// themselves. Mirrors what the grouped library renders.
List<World> libraryDisplayOrder(List<World> worlds) {
  final byId = {for (final w in worlds) w.id: w};
  final byParent = <String, List<World>>{};
  final roots = <World>[];
  for (final w in worlds) {
    if (_isLocation(w, byId)) {
      byParent.putIfAbsent(w.parentWorldId!, () => []).add(w);
    } else {
      roots.add(w);
    }
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  final out = <World>[];
  for (final r in roots) {
    out.add(r);
    out.addAll(_subtreeOf(r.id, byParent));
  }
  // Dangling-parent places (their parent row is gone) still need a slot.
  final seen = {for (final w in out) w.id};
  out.addAll([
    for (final w in worlds)
      if (!seen.contains(w.id)) w,
  ]);
  return out;
}

/// The worlds that get a card: everything that is not a location. A place
/// whose parent row is gone counts here, as it does in the flat grid.
int topLevelWorldCount(List<World> worlds) {
  final byId = {for (final w in worlds) w.id: w};
  return worlds.where((w) => !_isLocation(w, byId)).length;
}

/// How deep [place] sits below [rootId]: 1 for a direct child, 2 for a
/// room in a building. Stops on a broken or ringed chain.
int placeDepthUnder(String rootId, World place, World? Function(String) byId) {
  var depth = 1;
  var cur = place;
  final seen = <String>{cur.id};
  while (cur.parentWorldId != null && cur.parentWorldId != rootId) {
    final parent = byId(cur.parentWorldId!);
    if (parent == null || !seen.add(parent.id)) break;
    cur = parent;
    depth++;
  }
  return depth;
}

/// Children count for a world card's "N places" chip.
int placesUnder(String rootId, List<World> worlds) {
  final byId = {for (final w in worlds) w.id: w};
  // Direct children only for the chip — "2 places inside" on the card,
  // per the mockup, not the whole subtree.
  return worlds
      .where((w) => w.parentWorldId != null && byId[w.parentWorldId] != null)
      .where((w) => byId[w.parentWorldId]!.id == rootId)
      .length;
}
