// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The warm dialog's confirm button is readable on its own fill: dark ink on
// dark mode's bright amber (white there read at about 2:1), white on light
// mode's deep amber and on the red of a destructive confirm.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/accent_fit.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/app_theme.dart';
import 'package:front_porch_ai/ui/theme/themes/app_theme_id.dart';
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

  testWidgets('a custom accent confirm reads in every theme and mode', (
    tester,
  ) async {
    // A pale violet once drew white on the dark fill at 2.7:1.
    const picks = [Color(0xFFA78BFA), Color(0xFFFFFF00), Color(0xFF1E3A8A)];
    for (final theme in AppThemeId.values) {
      for (final pick in picks) {
        final palettes = withCustomAccent(theme.palettes, pick);
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(palettes: palettes, brightness: brightness),
              home: Scaffold(
                body: Builder(
                  builder: (context) =>
                      warmDialogConfirm(context, label: 'OK', onPressed: () {}),
                ),
              ),
            ),
          );
          final style = tester
              .widget<ElevatedButton>(find.byType(ElevatedButton))
              .style!;
          final fill = style.backgroundColor!.resolve(const {})!;
          final ink = style.foregroundColor!.resolve(const {})!;
          expect(
            contrastRatio(ink, fill),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.key} ${brightness.name} ${accentHex(pick)}',
          );
        }
      }
    }
  });
}
