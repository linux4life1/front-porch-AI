// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure guards for the Worlds library planner and the parent/reachable
// resolvers (locations slice 3). No widget tree: these pin the exact
// grouping, filter and candidate rules the UI renders, so a regression in
// the plan shows here and not in a screenshot.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';

World w(
  String name, {
  String? parent,
  bool model = false,
  bool climate = true,
}) {
  final world = World(
    id: name,
    name: name,
    lorebook: Lorebook(entries: []),
    parentWorldId: parent,
    climateEnabled: climate,
  );
  if (model) world.placeTraits['madeBy'] = 'model';
  return world;
}

World? Function(String) index(List<World> all) {
  final byId = {for (final x in all) x.id: x};
  return (id) => byId[id];
}

void main() {
  group('planWorldLibrary', () {
    // A town with two places, a lone childless world, a place whose parent
    // was deleted (dangling), and a model-made place.
    final town = w('Bletchfield');
    final hall = w('Town Hall', parent: 'Bletchfield');
    final tea = w('Tea Rooms', parent: 'Bletchfield');
    final station = w('Red Dust Station');
    final ghost = w('Ghost Room', parent: 'gone');
    final shadow = w('Shadow Hall', parent: 'Bletchfield', model: true);

    final library = [town, station, hall, tea, ghost, shadow];

    test('all: roots with children become sections; childless + dangling go '
        'flat; children sorted by name', () {
      final plan = planWorldLibrary(
        worlds: library,
        filter: WorldLibraryFilter.all,
      );
      expect(plan.sections.single.root.id, 'Bletchfield');
      // name order: Shadow Hall, Tea Rooms, Town Hall.
      expect(plan.sections.single.places.map((p) => p.id), [
        'Shadow Hall',
        'Tea Rooms',
        'Town Hall',
      ]);
      // The town renders through its section only — never also in flat.
      expect(plan.flat.map((f) => f.id), ['Red Dust Station', 'Ghost Room']);
      // Three places under the town — the ghost's dangling parent is flat
      // cargo, not anyone's child.
    });

    test('model made: only the flagged worlds, at any depth, flat', () {
      final plan = planWorldLibrary(
        worlds: library,
        filter: WorldLibraryFilter.modelMade,
      );
      expect(plan.sections, isEmpty);
      expect(plan.flat.map((f) => f.id), ['Shadow Hall']);
    });

    test('a library with no locations is flat — the pre-locations shape', () {
      final plan = planWorldLibrary(
        worlds: [station],
        filter: WorldLibraryFilter.all,
      );
      expect(plan.sections, isEmpty);
      expect(plan.flat.map((f) => f.id), ['Red Dust Station']);
    });

    test('placesUnder counts direct children only, resolved parents', () {
      expect(placesUnder('Bletchfield', library), 3);
      // Dangling parent id counts under nobody.
      expect(placesUnder('gone', library), 0);
    });
  });

  group('libraryDisplayOrder', () {
    test('roots first with subtrees beneath, dangling parents last', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final room = w('Room', parent: 'Town Hall');
      final cafe = w('Cafe', parent: 'Bletchfield');
      final lone = w('Red Dust Station');
      final ghost = w('Ghost Room', parent: 'gone');
      final order = libraryDisplayOrder([
        room,
        lone,
        cafe,
        ghost,
        hall,
        town,
      ]).map((x) => x.id).toList();
      // Roots come in library order; each root is immediately followed by
      // its subtree, children by name. The dangling "Ghost Room" reads as
      // a root (its parent row is gone) — never hidden, never orphaned.
      expect(order, [
        'Red Dust Station',
        'Ghost Room',
        'Bletchfield',
        'Cafe',
        'Town Hall',
        'Room',
      ]);
    });
  });

  group('parentPickCandidates', () {
    test(
      'excludes self and descendants; a childless root can adopt a depth-1',
      () {
        final town = w('Bletchfield');
        final hall = w('Town Hall', parent: 'Bletchfield');
        final room = w('Room', parent: 'Town Hall');
        final lone = w('Lone');
        final all = [town, hall, room, lone];
        // Creating a new place: the depth-2 Room cannot be a parent (a child
        // would sit at depth 3), the rest can.
        final create = parentPickCandidates(null, all, index(all));
        expect(create.map((c) => c.id), ['Bletchfield', 'Town Hall', 'Lone']);
        // Re-parenting the town: its subtree already sits at the depth-2 cap
        // (room), so nothing can take it — under its own children rings,
        // under the lone root the room would land at depth 3.
        final reparent = parentPickCandidates(town, all, index(all));
        expect(reparent, isEmpty);
        // A shallower town (childless) could go under Lone.
        final shallowTown = w('Quiet Ville');
        final moveUp = parentPickCandidates(shallowTown, [
          ...all,
          shallowTown,
        ], index([...all, shallowTown]));
        expect(moveUp.map((c) => c.id), containsAll(['Lone', 'Bletchfield']));
      },
    );
  });

  group('reachablePlaces', () {
    test('self, parent, children and siblings — one move step', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final tea = w('Tea Rooms', parent: 'Bletchfield');
      final room = w('Back Room', parent: 'Town Hall');
      final far = w('Red Dust Station');
      final all = [town, hall, tea, room, far];
      final reach = reachablePlaces(hall, all, index(all));
      expect(reach.map((r) => r.id).toSet(), {
        'Town Hall',
        'Bletchfield',
        'Back Room',
        'Tea Rooms',
      });
      expect(reach.map((r) => r.id), isNot(contains('Red Dust Station')));
    });

    test('a root reaches its children but has no parent or siblings', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final far = w('Red Dust Station');
      final reach = reachablePlaces(town, [
        town,
        hall,
        far,
      ], index([town, hall, far]));
      expect(reach.map((r) => r.id).toSet(), {'Bletchfield', 'Town Hall'});
    });
  });

  group('isModelMade', () {
    test('reads the madeBy trait, ignores other values', () {
      expect(w('A', model: true).isModelMade, isTrue);
      expect(w('B').isModelMade, isFalse);
      final forged = w('C');
      forged.placeTraits['madeBy'] = 'wizard';
      expect(forged.isModelMade, isFalse);
    });
  });

  // Hostile review #592: the ring-flat and cycle-safe-walk fixes shipped
  // without a guard. Each test below goes red when its fix is reverted.
  group('direct-DB rings (review #592)', () {
    test('parentPickCandidates does not stack-overflow on a cycle', () {
      // two worlds that are each other's parent — the state the save path
      // now refuses but a hand-edited DB already holds. Earth is the
      // candidate that forces the height walk of self's subtree: without
      // the seen set A→B→A recursed until the stack died.
      final earth = w('Earth');
      final a = w('A');
      final b = w('B');
      a.parentWorldId = 'B';
      b.parentWorldId = 'A';
      final all = [earth, a, b];
      final candidates = parentPickCandidates(a, all, index(all));
      // The ring inflates A's height past the cap, so even the clean
      // root is conservatively refused — and we got here at all.
      expect(candidates, isEmpty);
      // Self-parented editing world: same walk, same promise.
      final self = w('Self');
      self.parentWorldId = 'Self';
      expect(
        () => parentPickCandidates(self, [self, earth], index([self, earth])),
        returnsNormally,
      );
    });

    test('planWorldLibrary renders ring members flat, never drops them', () {
      final a = w('A');
      final b = w('B');
      a.parentWorldId = 'B';
      b.parentWorldId = 'A';
      final plan = planWorldLibrary(
        worlds: [a, b],
        filter: WorldLibraryFilter.all,
      );
      // No root can host them (each is a location); they surface in flat
      // so the author can still fix them.
      expect(plan.sections, isEmpty);
      expect(plan.flat.map((f) => f.id).toSet(), {'A', 'B'});
    });

    test('reachablePlaces lists the setting once on a self-parented row', () {
      final s = w('Loop');
      s.parentWorldId = 'Loop';
      final reach = reachablePlaces(s, [s], index([s]));
      // Exact list: the pre-fix walk listed the Setting twice (once as
      // self, once as its own resolved parent).
      expect(reach.map((r) => r.id), ['Loop']);
      // And its child does not double through the coincident sibling loop.
      final kid = w('Kid', parent: 'Loop');
      final withKid = reachablePlaces(s, [s, kid], index([s, kid]));
      expect(withKid.where((r) => r.id == 'Kid').length, 1);
    });
  });

  group('top-level worlds and depth', () {
    test('only worlds count as worlds: places inside them do not', () {
      final town = w('Bletchfield');
      final all = [
        town,
        w('Town Hall', parent: 'Bletchfield'),
        w('Back Room', parent: 'Town Hall'),
        w('Red Dust Station'),
        // A place whose world row is gone still gets a card, so it counts.
        w('Ghost Room', parent: 'gone'),
      ];
      expect(topLevelWorldCount(all), 3);
    });

    test('placeDepthUnder: 1 inside the world, 2 inside a building', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final room = w('Back Room', parent: 'Town Hall');
      final all = [town, hall, room];
      expect(placeDepthUnder('Bletchfield', hall, index(all)), 1);
      expect(placeDepthUnder('Bletchfield', room, index(all)), 2);
    });
  });

  group('bulkDeletePlan', () {
    test('sends only doomed rows with no doomed ancestor and counts the '
        'hand-made places that go with them', () {
      final wiki = w('Wiki World', model: true);
      final keep = w('Wiki Keep', parent: 'Wiki World', model: true);
      final cellar = w('Cellar', parent: 'Wiki Keep');
      final garden = w('My Garden', parent: 'Wiki World');
      final lone = w('Lone Mint', model: true);
      final other = w('Bletchfield');
      final all = [wiki, keep, cellar, garden, lone, other];
      final plan = bulkDeletePlan([wiki, keep, lone], all, index(all));
      expect(plan.roots.map((x) => x.id), ['Wiki World', 'Lone Mint']);
      expect(plan.alsoInside, 2, reason: 'Cellar and My Garden go too');
    });
  });
}
