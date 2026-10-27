// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create World with the name left blank used to save a nameless world (a "?"
// card, "World created successfully"). The dialog now stays open, saves
// nothing and says "Give your world a name." under the name field. Editing an
// existing world down to a blank name is refused the same way. Header
// AnimationController.repeat() — bounded pumps only, never pumpAndSettle.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import '../../helpers/double_tap.dart';

import '../../golden/support/fakes.dart';

/// Records what the dialog asks to save or rename.
class _RecordingWorlds extends FakeWorldRepository {
  _RecordingWorlds([super.worlds]);

  final saved = <model.World>[];
  final renamed = <String>[];

  @override
  Future<void> saveWorld(model.World world) async => saved.add(world);

  @override
  Future<void> renameWorld(model.World world, String newName) async =>
      renamed.add(newName);
}

/// Holds every save open until [release], like a slow disk.
class _SlowWorlds extends _RecordingWorlds {
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> saveWorld(model.World world) async {
    saved.add(world);
    await _gate.future;
  }
}

Future<void> _bounded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _pumpPage(WidgetTester tester, _RecordingWorlds worlds) async {
  tester.view.physicalSize = const Size(1280, 900);
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

Finder _nameField() => find.widgetWithText(TextField, 'World Name');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Create World with a blank name saves nothing and says why', (
    tester,
  ) async {
    final worlds = _RecordingWorlds();
    await _pumpPage(tester, worlds);
    await tester.tap(find.widgetWithText(ElevatedButton, 'New World'));
    await _bounded(tester);

    await tester.enterText(_nameField(), '   ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await _bounded(tester);

    expect(worlds.saved, isEmpty);
    expect(find.text('Give your world a name.'), findsOneWidget);
    expect(find.text('World created successfully'), findsNothing);
    // Still open, so the person can type a name.
    expect(find.widgetWithText(ElevatedButton, 'Create World'), findsOneWidget);

    // Typing clears the message; a real name then saves, trimmed. A new
    // world also names where its chats start, saved inside it right after.
    await tester.enterText(_nameField(), '  Harbor Town ');
    await _bounded(tester);
    expect(find.text('Give your world a name.'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('world-starting-place-name')),
      'The Quay',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await _bounded(tester);
    expect(worlds.saved.map((w) => w.name), ['Harbor Town', 'The Quay']);
  });

  testWidgets('Edit World cannot blank an existing name', (tester) async {
    final existing = model.World(
      name: 'Harbor Town',
      lorebook: Lorebook(entries: []),
    );
    final worlds = _RecordingWorlds([existing]);
    await _pumpPage(tester, worlds);
    await tester.tap(find.text('Harbor Town').first);
    await _bounded(tester);
    expect(find.text('Edit World'), findsOneWidget);

    await tester.enterText(_nameField(), '');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await _bounded(tester);

    expect(worlds.saved, isEmpty);
    expect(worlds.renamed, isEmpty);
    expect(existing.name, 'Harbor Town');
    expect(find.text('Give your world a name.'), findsOneWidget);
  });

  testWidgets('a second Create World tap during a slow save saves nothing', (
    tester,
  ) async {
    final worlds = _SlowWorlds();
    await _pumpPage(tester, worlds);
    await tester.tap(find.widgetWithText(ElevatedButton, 'New World'));
    await _bounded(tester);

    await tester.enterText(_nameField(), 'The Cinder Wastes');
    await tester.enterText(
      find.byKey(const Key('world-starting-place-name')),
      'Ash Gate',
    );
    final create = find.widgetWithText(ElevatedButton, 'Create World');
    // Back to back, no frame between: the second tap runs the closure the
    // first tap's build handed out, before `saving` disables the button.
    await tester.tap(create);
    await tester.tap(create, warnIfMissed: false);
    await _bounded(tester);
    expect(worlds.saved, hasLength(1));

    worlds.release();
    await _bounded(tester);
    expect(create, findsNothing);
    // One world and its one starting place: the second tap saved nothing.
    expect(worlds.saved.map((w) => w.name), ['The Cinder Wastes', 'Ash Gate']);
  });

  testWidgets('Add a place inside words the dialog as a place in its parent', (
    tester,
  ) async {
    final earth = model.World(
      id: 'earth-1',
      name: 'Earth',
      lorebook: Lorebook(
        entries: [
          LorebookEntry(key: 'sea', content: 'Salt water.'),
          LorebookEntry(key: 'moon', content: 'One moon.')..enabled = false,
        ],
      ),
    );
    final town = model.World(
      name: 'Harbor Town',
      lorebook: Lorebook(entries: []),
      parentWorldId: 'earth-1',
      climateEnabled: false,
    );
    final worlds = _RecordingWorlds([earth, town]);
    await _pumpPage(tester, worlds);
    // Earth has a place, so "Add a place inside" lives in its places panel.
    await tester.tap(find.byKey(const Key('places-chip-earth-1')));
    await _bounded(tester);
    await tester.ensureVisible(find.byKey(const Key('place-add-inside')).first);
    await _bounded(tester);
    await tester.tap(find.byKey(const Key('place-add-inside')).first);
    await _bounded(tester);

    // Names the parent everywhere a top-level create would say "World".
    expect(find.text('Add a place to Earth'), findsOneWidget);
    expect(find.text('Create World'), findsNothing);
    expect(find.widgetWithText(TextField, 'World Name'), findsNothing);
    expect(find.widgetWithText(TextField, 'Place name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.text("This place's lore (0)"), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('world-inherited-lore')),
        matching: find.textContaining('1 lore entry from Earth'),
      ),
      findsOneWidget,
    );

    // Own climate opens the climate editor under the Inherit / Own pair,
    // not back up in Basic Information.
    expect(find.text('Atmosphere'), findsNothing);
    await tester.ensureVisible(find.text('Own climate'));
    await tester.tap(find.text('Own climate'));
    await _bounded(tester);
    expect(find.text('Atmosphere'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Climate')).dy,
      greaterThan(tester.getTopLeft(find.text('Own climate')).dy),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Place name'),
      'The Lighthouse',
    );
    final add = find.widgetWithText(ElevatedButton, 'Add place');
    await tester.ensureVisible(add);
    await doubleTapNoFrame(tester, add);
    await _bounded(tester);
    expect(worlds.saved, hasLength(1));
    expect(worlds.saved.single.parentWorldId, 'earth-1');
    expect(find.text('Place added'), findsOneWidget);
  });

  testWidgets('a weather-off world says so in the place editor and its own', (
    tester,
  ) async {
    final earth = model.World(
      id: 'earth-1',
      name: 'Earth',
      lorebook: Lorebook(entries: []),
      climateEnabled: false,
    );
    final greenhouse = model.World(
      id: 'greenhouse-1',
      name: 'The Greenhouse',
      lorebook: Lorebook(entries: []),
      parentWorldId: 'earth-1',
      climateEnabled: true,
    );
    final worlds = _RecordingWorlds([earth, greenhouse]);
    await _pumpPage(tester, worlds);
    await tester.tap(find.byKey(const Key('places-chip-earth-1')));
    await _bounded(tester);

    // The places panel: an owned climate under a weather-off world is
    // kept but paused, and the panel says the switch covers all.
    expect(find.textContaining('Own climate · paused'), findsOneWidget);
    expect(
      find.textContaining('Weather off for the whole world'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('place-add-inside')).first);
    await _bounded(tester);
    await tester.tap(find.byKey(const Key('place-add-inside')).first);
    await _bounded(tester);
    expect(find.byKey(const Key('world-weather-off-note')), findsOneWidget);
    expect(find.text('Weather is off for Earth'), findsOneWidget);
    expect(find.text('No weather: Earth has weather off.'), findsOneWidget);
    expect(find.text("No effect while Earth's weather is off"), findsOneWidget);

    // Own climate still opens the editor, marked paused.
    await tester.ensureVisible(find.text('Own climate'));
    await tester.tap(find.text('Own climate'));
    await _bounded(tester);
    expect(find.text("Paused while Earth's weather is off"), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Atmosphere'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _bounded(tester);
    final discard = find.text('Discard');
    if (discard.evaluate().isNotEmpty) {
      await tester.tap(discard);
      await _bounded(tester);
    }

    // The world's own editor lists the place its switch pauses. Tapping
    // a world card opens its editor.
    await tester.tap(find.text('Earth').first);
    await _bounded(tester);
    expect(find.byKey(const Key('world-paused-places-note')), findsOneWidget);
    expect(find.text('1 place inside sets its own climate'), findsOneWidget);
  });

  testWidgets(
    'weather-off wording stays at full ink, outside the dimmed editor',
    (tester) async {
      final earth = model.World(
        id: 'earth-1',
        name: 'Earth',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
      );
      final worlds = _RecordingWorlds([earth]);
      await _pumpPage(tester, worlds);

      await tester.tap(find.byKey(const Key('place-add-inside')).first);
      await _bounded(tester);
      await tester.ensureVisible(find.text('Own climate'));
      await tester.tap(find.text('Own climate'));
      await _bounded(tester);

      Color? inkOf(Finder f) => tester.widget<Text>(f).style?.color;
      final ink = AppColors.textPrimary(tester.element(find.text('Paused')));
      final body = find.descendant(
        of: find.byKey(const Key('world-weather-off-note')),
        matching: find.textContaining('Earth'),
      );
      expect(body, findsWidgets);
      for (final e in body.evaluate()) {
        expect((e.widget as Text).style?.color, ink);
      }
      expect(inkOf(find.text('Paused')), ink);
      expect(inkOf(find.text("Paused while Earth's weather is off")), ink);
      expect(inkOf(find.text('No weather: Earth has weather off.')), ink);
      expect(
        find.ancestor(of: find.text('Paused'), matching: find.byType(Opacity)),
        findsNothing,
      );
    },
  );

  testWidgets('a new world will not save until it names where chats start; '
      'the place is saved inside it and starred', (tester) async {
    final worlds = _RecordingWorlds();
    await _pumpPage(tester, worlds);
    await tester.tap(find.widgetWithText(ElevatedButton, 'New World'));
    await _bounded(tester);
    expect(find.text('Where chats start'), findsOneWidget);

    await tester.enterText(_nameField(), 'Bletchfield');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await _bounded(tester);
    expect(worlds.saved, isEmpty);
    expect(
      find.text('Name the place where chats in this world start.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('world-starting-place-name')),
      'Tea Rooms',
    );
    await tester.enterText(
      find.byKey(const Key('world-starting-place-description')),
      'Steam and gossip.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await _bounded(tester);

    expect(worlds.saved, hasLength(2));
    final world = worlds.saved.first;
    final tea = worlds.saved.last;
    expect(tea.name, 'Tea Rooms');
    expect(tea.description, 'Steam and gossip.');
    expect(tea.parentWorldId, world.id);
    expect(tea.climateEnabled, isFalse, reason: 'inherits the weather');
    expect(world.defaultPlaceId, tea.id);
  });

  testWidgets('editing a world with places picks among them, starting on '
      'its starred place', (tester) async {
    final town = model.World(
      id: 'town-1',
      name: 'Bletchfield',
      lorebook: Lorebook(entries: []),
    )..defaultPlaceId = 'tea-1';
    final worlds = _RecordingWorlds([
      town,
      model.World(
        id: 'tea-1',
        name: 'Tea Rooms',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
        parentWorldId: 'town-1',
      ),
      model.World(
        id: 'hall-1',
        name: 'Town Hall',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
        parentWorldId: 'town-1',
      ),
    ]);
    await _pumpPage(tester, worlds);
    // Tapping a world card opens its editor.
    await tester.tap(find.text('Bletchfield').first);
    await _bounded(tester);
    expect(find.text('Edit World'), findsOneWidget);

    final picker = find.byKey(const Key('world-starting-place-picker'));
    expect(
      find.descendant(of: picker, matching: find.text('Tea Rooms')),
      findsOneWidget,
    );
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await _bounded(tester);
    await tester.tap(find.text('Town Hall').last);
    await _bounded(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
    await _bounded(tester);

    expect(worlds.saved.single.id, 'town-1');
    expect(town.defaultPlaceId, 'hall-1');
  });
}
