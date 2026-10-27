// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The starting-place star in the Worlds library: a place inside a world
// gets a star like the canonical-avatar star in the portrait gallery. One
// tap makes it where chats attached to the world start (the world's header
// card then says "Chats start at <place>"), starring another place moves
// the star, and the starred place stays starred when tapped: every world
// keeps a starting place. The seed and
// attach behaviour behind the star is pinned in world_repository_test and
// the world_starting_place E2E. Header AnimationController.repeat() —
// bounded pumps only, never pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';

import '../../golden/support/fakes.dart';

/// Records each star write and applies it the way the repository does, so
/// the page repaints from the cache like it would in the app.
class _StarWorlds extends FakeWorldRepository {
  _StarWorlds(super.worlds);

  final writes = <String?>[];

  @override
  Future<void> setDefaultPlace(model.World world, String? placeId) async {
    writes.add(placeId);
    world.defaultPlaceId = placeId;
    notifyListeners();
  }
}

model.World _world(String id, {String? parent, bool climate = false}) =>
    model.World(
      id: id,
      name: id,
      description: '$id prose.',
      lorebook: Lorebook(entries: []),
      climateEnabled: climate,
      parentWorldId: parent,
    );

Future<void> _pumpLibrary(WidgetTester tester, _StarWorlds worlds) async {
  tester.view.physicalSize = const Size(1280, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(worlds.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<WorldRepository>.value(
      value: worlds,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
        home: const WorldManagementPage(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tapStar(WidgetTester tester, String placeId) async {
  final star = find.byKey(Key('place-star-$placeId'));
  await tester.ensureVisible(star);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(star);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('starring a place names it on the world card; starring another '
      'moves the star; tapping the starred one keeps it', (tester) async {
    final worlds = _StarWorlds([
      _world('Bletchfield', climate: true),
      _world('Tea Rooms', parent: 'Bletchfield'),
      _world('Town Hall', parent: 'Bletchfield'),
    ]);
    await _pumpLibrary(tester, worlds);

    expect(
      find.text('Star a place below: chats start there'),
      findsOneWidget,
      reason: 'a world with places and no start asks for one',
    );
    expect(find.byKey(const Key('place-star-Tea Rooms')), findsOneWidget);
    expect(
      find.byKey(const Key('place-star-Bletchfield')),
      findsNothing,
      reason: 'the world itself has no star; only places inside it do',
    );

    await _tapStar(tester, 'Tea Rooms');
    expect(worlds.writes, ['Tea Rooms']);
    expect(find.text('Chats start at Tea Rooms'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('place-star-Tea Rooms')),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
      reason: 'the starred place shows a filled star',
    );

    await _tapStar(tester, 'Town Hall');
    expect(worlds.writes.last, 'Town Hall');
    expect(find.text('Chats start at Town Hall'), findsOneWidget);
    expect(find.text('Chats start at Tea Rooms'), findsNothing);

    await _tapStar(tester, 'Town Hall');
    expect(worlds.writes, [
      'Tea Rooms',
      'Town Hall',
    ], reason: 'a world always keeps a starting place: no clear');
    expect(find.text('Chats start at Town Hall'), findsOneWidget);
  });
}
