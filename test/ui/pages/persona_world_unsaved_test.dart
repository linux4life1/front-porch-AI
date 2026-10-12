// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The persona editor and the world dialog used to drop typed work on back,
// Cancel, the close X or a click outside. They now ask when something
// changed and close quietly when nothing did. Both pages run a perpetual
// header animation, so only bounded pumps are used.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/user_persona_page.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';

import '../../golden/support/fakes.dart';

const _question = 'Discard unsaved changes?';

Future<void> _bounded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(page);
  await _bounded(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('world dialog', () {
    Future<void> openNewWorld(WidgetTester tester) async {
      final worlds = FakeWorldRepository();
      addTearDown(worlds.dispose);
      await _pump(
        tester,
        ChangeNotifierProvider<WorldRepository>.value(
          value: worlds,
          child: const MaterialApp(home: WorldManagementPage()),
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'New World'));
      await _bounded(tester);
      expect(find.widgetWithText(ElevatedButton, 'Create World'), findsOne);
    }

    testWidgets('closes quietly when nothing was typed', (tester) async {
      await openNewWorld(tester);
      await tester.tap(find.byTooltip('Close'));
      await _bounded(tester);
      expect(find.text(_question), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Create World'), findsNothing);
    });

    testWidgets('a typed name asks before the X or Cancel drops it', (
      tester,
    ) async {
      await openNewWorld(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'World Name'),
        'Harbor Town',
      );
      await tester.tap(find.byTooltip('Close'));
      await _bounded(tester);
      expect(find.text(_question), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await _bounded(tester);
      expect(find.text('Harbor Town'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _bounded(tester);
      await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
      await _bounded(tester);
      expect(find.widgetWithText(ElevatedButton, 'Create World'), findsNothing);
    });
  });

  group('persona editor', () {
    Future<void> openNewPersona(WidgetTester tester) async {
      final personas = FakeUserPersonaService();
      addTearDown(personas.dispose);
      await _pump(
        tester,
        ChangeNotifierProvider<UserPersonaService>.value(
          value: personas,
          child: const MaterialApp(home: UserPersonaPage()),
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'New Persona'));
      await _bounded(tester);
      expect(find.text('Create Persona'), findsOneWidget);
    }

    testWidgets('back from an empty form returns to the list quietly', (
      tester,
    ) async {
      await openNewPersona(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _bounded(tester);
      expect(find.text(_question), findsNothing);
      expect(find.text('User Personas'), findsOneWidget);
    });

    testWidgets('back from a typed persona asks; Keep editing keeps it', (
      tester,
    ) async {
      await openNewPersona(tester);
      await tester.enterText(find.byType(TextField).first, 'Porch Sitter');
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _bounded(tester);
      expect(find.text(_question), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await _bounded(tester);
      expect(find.text('Create Persona'), findsOneWidget);
      expect(find.text('Porch Sitter'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await _bounded(tester);
      await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
      await _bounded(tester);
      expect(find.text('User Personas'), findsOneWidget);
    });
  });
}
