// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/studio_slider_card.dart';

void main() {
  testWidgets(
    'StudioSliderCard renders label, input box, and responds to changes',
    (tester) async {
      double current = 0.70;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => StudioSliderCard(
                label: 'Temperature',
                value: current,
                min: 0.0,
                max: 2.0,
                defaultVal: 0.70,
                dangerMax: 1.60,
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

  testWidgets(
    'StudioSliderCard pumps stored out-of-range value without crashing',
    (tester) async {
      // Stored value 2.50 exceeds max of 2.00
      double current = 2.50;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSliderCard(
              label: 'Temperature',
              value: current,
              min: 0.0,
              max: 2.0,
              defaultVal: 0.70,
              dangerMax: 1.60,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify no assertion error occurred and unclamped text is rendered
      expect(find.text('2.50'), findsOneWidget);

      final slider = tester.widget<Slider>(find.byType(Slider));
      // Slider thumb value must clamp to max so Slider does not throw
      expect(slider.value, 2.0);
    },
  );

  testWidgets(
    'StudioSliderCard focus and blur without edits does not call onChanged',
    (tester) async {
      bool changed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StudioSliderCard(
                  label: 'Temperature',
                  value: 0.735,
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 0.70,
                  decimalPlaces: 3,
                  onChanged: (_) => changed = true,
                ),
                const TextField(key: ValueKey('other_field')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('0.735'), findsOneWidget);

      // Focus into StudioSliderCard's text field
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      // Blur by tapping another focusable widget
      await tester.tap(find.byKey(const ValueKey('other_field')));
      await tester.pump();

      // Verify onChanged was NOT triggered and text was not rewritten
      expect(changed, isFalse);
      expect(find.text('0.735'), findsOneWidget);
    },
  );

  testWidgets(
    'StudioSliderCard typing new value commits on blur with 0.00 precision',
    (tester) async {
      double? committed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                StudioSliderCard(
                  label: 'Min-P',
                  value: 0.10,
                  min: 0.0,
                  max: 0.25,
                  defaultVal: 0.10,
                  onChanged: (val) => committed = val,
                ),
                const TextField(key: ValueKey('blur_target')),
              ],
            ),
          ),
        ),
      );

      final inputFinder = find.byType(TextField).first;
      await tester.tap(inputFinder);
      await tester.pump();

      // Enter 0.18
      await tester.enterText(inputFinder, '0.18');
      await tester.pump();

      // Blur by tapping target
      await tester.tap(find.byKey(const ValueKey('blur_target')));
      await tester.pump();

      expect(committed, closeTo(0.18, 1e-5));
      expect(find.text('0.18'), findsOneWidget);
    },
  );
}
