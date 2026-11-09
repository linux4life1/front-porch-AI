// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/studio_slider_card.dart';

void main() {
  testWidgets(
    'StudioSliderCard renders label, input box, and responds to changes',
    (tester) async {
      double current = 0.7;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => StudioSliderCard(
                label: 'Temperature',
                value: current,
                min: 0.0,
                max: 1.6,
                defaultVal: 0.7,
                dangerMax: 1.25,
                onChanged: (val) => setState(() => current = val),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('0.70'), findsOneWidget);
    },
  );
}
