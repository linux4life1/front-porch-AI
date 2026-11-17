// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/studio_slider_track_shape.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  testWidgets(
    'StudioSliderTrackShape computes correct pip and danger metrics',
    (tester) async {
      const shape = StudioSliderTrackShape(
        min: 0.0,
        max: 1.0,
        defaultVal: 0.7,
        dangerMax: 0.85,
        dangerMin: 0.15,
        dangerActiveColor: AppColors.negativeAccent,
        dangerInactiveColor: AppColors.negativeAccent,
        pipColor: AppColors.slateMuted,
      );

      expect(shape.defaultVal, 0.7);
      expect(shape.dangerMax, 0.85);
      expect(shape.dangerMin, 0.15);
      expect(shape.normalizedDefault, closeTo(0.7, 1e-6));
      expect(shape.normalizedDangerMax, closeTo(0.85, 1e-6));
      expect(shape.normalizedDangerMin, closeTo(0.15, 1e-6));
    },
  );

  testWidgets(
    'StudioSliderTrackShape paints in LTR without errors',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SliderTheme(
              data: SliderThemeData(
                trackShape: const StudioSliderTrackShape(
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 0.70,
                  dangerMax: 1.60,
                  dangerActiveColor: AppColors.negativeAccent,
                  dangerInactiveColor: AppColors.negativeAccent,
                  pipColor: AppColors.slateMuted,
                ),
                trackHeight: 4,
              ),
              child: Slider(
                value: 1.80,
                min: 0.0,
                max: 2.0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Slider), findsOneWidget);
    },
  );

  testWidgets(
    'StudioSliderTrackShape paints in RTL without errors',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: SliderTheme(
                data: SliderThemeData(
                  trackShape: const StudioSliderTrackShape(
                    min: 0.0,
                    max: 2.0,
                    defaultVal: 0.70,
                    dangerMax: 1.60,
                    dangerActiveColor: AppColors.negativeAccent,
                    dangerInactiveColor: AppColors.negativeAccent,
                    pipColor: AppColors.slateMuted,
                  ),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: 1.80,
                  min: 0.0,
                  max: 2.0,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Slider), findsOneWidget);
    },
  );

  testWidgets(
    'StudioSliderTrackShape paints disabled state without errors',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SliderTheme(
              data: SliderThemeData(
                trackShape: const StudioSliderTrackShape(
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 0.70,
                  dangerMax: 1.60,
                  dangerActiveColor: AppColors.negativeAccent,
                  dangerInactiveColor: AppColors.negativeAccent,
                  pipColor: AppColors.slateMuted,
                ),
                trackHeight: 4,
              ),
              child: const Slider(
                value: 0.70,
                min: 0.0,
                max: 2.0,
                onChanged: null, // Disabled
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Slider), findsOneWidget);
    },
  );
}
