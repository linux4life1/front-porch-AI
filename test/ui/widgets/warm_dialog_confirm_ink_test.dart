// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The warm dialog's confirm button is readable on its own fill: dark ink on
// dark mode's bright amber (white there read at about 2:1), white on light
// mode's deep amber and on the red of a destructive confirm.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

Future<Color?> _ink(
  WidgetTester tester,
  Brightness brightness, {
  bool destructive = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Builder(
          builder: (context) => warmDialogConfirm(
            context,
            label: 'OK',
            onPressed: () {},
            destructive: destructive,
          ),
        ),
      ),
    ),
  );
  final style = tester
      .widget<ElevatedButton>(find.byType(ElevatedButton))
      .style;
  return style?.foregroundColor?.resolve(const {});
}

void main() {
  testWidgets('dark mode amber gets dark ink', (tester) async {
    expect(await _ink(tester, Brightness.dark), AppColors.onChaosAccent);
  });

  testWidgets('light mode amber keeps white', (tester) async {
    expect(await _ink(tester, Brightness.light), Colors.white);
  });

  testWidgets('a destructive confirm keeps white in both modes', (
    tester,
  ) async {
    expect(
      await _ink(tester, Brightness.dark, destructive: true),
      Colors.white,
    );
    expect(
      await _ink(tester, Brightness.light, destructive: true),
      Colors.white,
    );
  });
}
