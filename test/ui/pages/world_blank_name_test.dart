// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create World with the name left blank used to save a nameless world (a "?"
// card, "World created successfully"). The dialog now stays open, saves
// nothing and says "Give your world a name." under the name field. Editing an
// existing world down to a blank name is refused the same way. Header
// AnimationController.repeat() — bounded pumps only, never pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';

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

    // Typing clears the message; a real name then saves, trimmed.
    await tester.enterText(_nameField(), '  Harbor Town ');
    await _bounded(tester);
    expect(find.text('Give your world a name.'), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await _bounded(tester);
    expect(worlds.saved.single.name, 'Harbor Town');
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
}
