// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/studio_slider_track_shape.dart';

void main() {
  testWidgets(
    'StudioSliderTrackShape computes correct pip and danger metrics',
    (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final shape = StudioSliderTrackShape(
        min: 0.0,
        max: 1.0,
        defaultVal: 0.7,
        dangerMax: 0.85,
        context: ctx,
      );

      expect(shape.defaultVal, 0.7);
      expect(shape.dangerMax, 0.85);
      expect(shape.normalizedDefault, closeTo(0.7, 1e-6));
      expect(shape.normalizedDangerMax, closeTo(0.85, 1e-6));
    },
  );
}
