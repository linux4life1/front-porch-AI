// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Needs bars and the collapsed group member chips follow the needs bands
// (docs/design/needs-on-the-clock.md, "Bands"): amber from the urgent
// threshold down, red from the critical threshold down, their own colour
// above. The thresholds are the engine's, read through the accessors, so the
// pin holds whatever numbers the engine sets (40 and 25 in the v2 spec).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  late BuildContext ctx;

  Future<void> pump(WidgetTester tester, ThemeData theme, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return Center(child: SizedBox(width: 360, child: child));
            },
          ),
        ),
      ),
    );
  }

  for (final theme in [ThemeData.light(), ThemeData.dark()]) {
    final name = theme.brightness.name;

    for (final mini in [false, true]) {
      testWidgets('NeedsBar${mini ? ' (mini)' : ''} bands, $name', (
        tester,
      ) async {
        Future<Color> fillAt(int value) async {
          await pump(
            tester,
            theme,
            NeedsBar(need: 'hunger', value: value, mini: mini),
          );
          final bar = tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
          final fill = (bar.valueColor! as AlwaysStoppedAnimation<Color>).value;
          expect(
            tester.widget<Icon>(find.byType(Icon)).color,
            fill,
            reason: 'the icon follows the same band as the fill',
          );
          return fill;
        }

        final own = await fillAt(100);
        final amber = AppColors.porchAmberOf(ctx);
        final red = AppColors.negativeAccentOf(ctx);
        expect(own, isNot(amber));
        expect(own, isNot(red));

        expect(await fillAt(needUrgentThreshold + 1), own);
        expect(await fillAt(needUrgentThreshold), amber);
        expect(await fillAt(needCriticalThreshold + 1), amber);
        expect(await fillAt(needCriticalThreshold), red);
        expect(await fillAt(0), red);
      });
    }

    testWidgets('MiniNeedChip bands, $name', (tester) async {
      Future<Color> tintAt(int value) async {
        await pump(tester, theme, MiniNeedChip(name: 'hunger', value: value));
        return tester.widget<Text>(find.text('H$value')).style!.color!;
      }

      final quiet = await tintAt(100);
      expect(quiet, AppColors.textSecondary(ctx));
      expect(await tintAt(needUrgentThreshold + 1), quiet);
      expect(await tintAt(needUrgentThreshold), AppColors.porchAmberOf(ctx));
      expect(
        await tintAt(needCriticalThreshold + 1),
        AppColors.porchAmberOf(ctx),
      );
      expect(
        await tintAt(needCriticalThreshold),
        AppColors.negativeAccentOf(ctx),
      );
    });
  }
}
