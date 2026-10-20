// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A settings colour row keeps its swatch at the pane's right edge on a wide
// pane, even inside a start-aligned column, and drops it under the label on
// a pane too narrow for both.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

Future<void> _pump(WidgetTester tester, double width) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ColorRow(
                label: 'Dialogue (Quoted)',
                color: Colors.white,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a wide pane keeps the swatch at its right edge', (tester) async {
    await _pump(tester, 600);
    final swatch = tester.getRect(find.byType(IconButton));
    // The icon button sits inside the swatch's 1px border.
    expect(swatch.right, closeTo(600, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow pane puts the swatch under the label', (tester) async {
    await _pump(tester, 90);
    final label = tester.getRect(find.text('Dialogue (Quoted)'));
    final swatch = tester.getRect(find.byType(IconButton));
    expect(swatch.top, greaterThanOrEqualTo(label.bottom));
    expect(tester.takeException(), isNull);
  });
}
