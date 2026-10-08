// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library phase 2: a box dragged to the bottom edge of the grid scrolls it,
// and keeps picking the cards that scroll into the box — cards that were
// never built when the drag began.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_gesture_harness.dart';

void main() {
  late GestureLibrary lib;

  setUp(() async {
    lib = await GestureLibrary.create([
      for (var i = 0; i < 42; i++) 'C${i.toString().padLeft(2, '0')}',
    ]);
  });

  tearDown(() => lib.dispose());

  testWidgets('a box at the bottom edge scrolls the grid and keeps picking', (
    tester,
  ) async {
    await lib.pump(tester, size: const Size(1400, 760));
    final grid = find.byType(GridView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: grid, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.pixels, 0);
    expect(find.text('C41'), findsNothing, reason: 'last row not built yet');

    final start = tester.getCenter(find.text('C00'));
    final bottom = tester.getBottomLeft(grid).dy - 8;
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await mouse.moveTo(Offset(start.dx + 40, bottom - 100));
    await tester.pump();
    await mouse.moveTo(Offset(start.dx + 40, bottom));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(position.pixels, greaterThan(0), reason: 'the grid scrolled');
    expect(
      lib.selection.characterIds,
      contains('C35'),
      reason: 'a first-column card from the last row joined as it scrolled in',
    );
    await mouse.up();
    await tester.pump();
  });
}
