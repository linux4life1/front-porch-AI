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

// Settings > Chat Appearance "Select Color" opened as a stock white dialog
// with blue buttons. It now opens in the warm-porch dialog, and the picker
// itself still hands back what the user chose.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  const initial = Color(0xFF3B82F6);

  Future<List<Color>> openPicker(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final picked = <Color>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showColorPicker(context, initial, picked.add),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('Select Color opens in the warm-porch dialog', (tester) async {
    await openPicker(tester);
    final dialog = find.widgetWithText(WarmDialog, 'Select Color');
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(AlertDialog)),
      findsOneWidget,
      reason: 'one dialog, the warm one, not a stock dialog inside it',
    );
  });

  testWidgets('a quick-pick swatch returns its color', (tester) async {
    final picked = await openPicker(tester);
    final emerald = AppColors.presetColors[1];
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == emerald,
      ),
    );
    await tester.pumpAndSettle();
    expect(picked, [emerald]);
    expect(find.text('Select Color'), findsNothing);
  });

  testWidgets('OK keeps the current color, Cancel changes nothing', (
    tester,
  ) async {
    final picked = await openPicker(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
    await tester.pumpAndSettle();
    expect(picked, [initial]);
  });
}
