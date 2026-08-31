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

// Create World dialog: the footer is a Column sibling under a bounded
// Expanded scroll body, so Climate / Place traits / lorebook empty-state
// never paint through Save. Header AnimationController.repeat() — bounded
// pumps only, never pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';
import 'package:front_porch_ai/ui/pages/worlds/place_traits_editor.dart';

import '../../golden/support/fakes.dart';

Finder _createWorldBtn() => find.widgetWithText(ElevatedButton, 'Create World');

Finder _newWorldBtn() => find.widgetWithText(ElevatedButton, 'New World');

Finder _scrollBody() => find.byType(SingleChildScrollView);

void _expectFullyAboveFooter(
  WidgetTester tester,
  Finder content,
  String reason,
) {
  final c = tester.getRect(content);
  final footer = tester.getRect(_createWorldBtn());
  final body = tester.getRect(_scrollBody());
  expect(
    c.top,
    greaterThanOrEqualTo(body.top - 0.5),
    reason: '$reason: top clipped by scroll (content=$c body=$body)',
  );
  expect(
    c.bottom,
    lessThanOrEqualTo(body.bottom + 0.5),
    reason: '$reason: bottom clipped by scroll (content=$c body=$body)',
  );
  expect(
    c.bottom,
    lessThanOrEqualTo(footer.top + 0.5),
    reason: '$reason: bottom ${c.bottom} below footer.top ${footer.top}',
  );
  expect(
    c.overlaps(footer),
    isFalse,
    reason: '$reason: overlaps footer (content=$c footer=$footer)',
  );
}

Future<void> _pumpPage(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final worlds = FakeWorldRepository();
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
  // Header glow ticker — two bounded frames, never settle.
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _openCreate(WidgetTester tester) async {
  await tester.tap(_newWorldBtn());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(_createWorldBtn(), findsOneWidget);
}

Future<void> _bounded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(1280, 720), Size(800, 600)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('Create World climate ON at rest — footer clear ($tag)', (
      tester,
    ) async {
      await _pumpPage(tester, size);
      await _openCreate(tester);

      expect(
        find.text(
          'Shown on the Worlds grid and packed into .fpworld. '
          'Required to share on the Stoop.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Optional art'), findsNothing);

      _expectFullyAboveFooter(
        tester,
        find.text('Climate, weather, and place traits'),
        '$tag climate toggle title',
      );
      _expectFullyAboveFooter(
        tester,
        find.byType(Switch).first,
        '$tag climate switch',
      );
      _expectFullyAboveFooter(
        tester,
        find.text('Climate'),
        '$tag Climate picker label',
      );
      _expectFullyAboveFooter(
        tester,
        find.byKey(const Key('world-climate-picker')),
        '$tag Climate picker dropdown',
      );
      _expectFullyAboveFooter(
        tester,
        find.text('Temperate'),
        '$tag Climate picker Temperate',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Create World climate ON after traits visible — footer clear ($tag)',
      (tester) async {
        await _pumpPage(tester, size);
        await _openCreate(tester);

        await tester.ensureVisible(find.byType(PlaceTraitsEditor));
        await _bounded(tester);

        _expectFullyAboveFooter(
          tester,
          find.text('Atmosphere'),
          '$tag Atmosphere',
        );
        _expectFullyAboveFooter(tester, find.text('Gravity'), '$tag Gravity');
        _expectFullyAboveFooter(
          tester,
          find.text('No lorebook entries yet'),
          '$tag lorebook empty-state',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Create World climate OFF — lorebook above footer ($tag)', (
      tester,
    ) async {
      await _pumpPage(tester, size);
      await _openCreate(tester);

      await tester.tap(find.byType(Switch).first);
      await _bounded(tester);

      expect(find.text('Climate'), findsNothing);
      expect(find.byType(PlaceTraitsEditor), findsNothing);

      await tester.ensureVisible(find.text('No lorebook entries yet'));
      await _bounded(tester);
      _expectFullyAboveFooter(
        tester,
        find.text('No lorebook entries yet'),
        '$tag lorebook empty-state climate OFF',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
