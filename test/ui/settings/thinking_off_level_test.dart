// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Generation: Off is the first level of the thinking control (no
// separate switch); picking a level while off turns thinking on; a slider
// names both ends of its track.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('picking a level while off turns thinking on first', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _host(
        ThinkingStrengthControl(
          value: 'low',
          modelId: '',
          thinkingOn: false,
          onTurnOff: () => calls.add('off'),
          onTurnOn: () => calls.add('on'),
          onChanged: (v) => calls.add(v),
        ),
      ),
    );
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('High'));
    expect(calls, ['on', 'high']);
  });

  testWidgets('Off turns thinking off, unless it is disabled', (tester) async {
    var offs = 0;
    Widget build(bool disabled) => _host(
      ThinkingStrengthControl(
        value: 'low',
        thinkingOn: true,
        offDisabled: disabled,
        onTurnOff: () => offs++,
        onTurnOn: () {},
        onChanged: (_) {},
      ),
    );
    await tester.pumpWidget(build(false));
    await tester.tap(find.text('Off'));
    expect(offs, 1);
    await tester.pumpWidget(build(true));
    await tester.tap(find.text('Off'));
    expect(offs, 1);
  });

  testWidgets('a slider shows both ends of its track', (tester) async {
    await tester.pumpWidget(
      _host(
        StudioSliderCard(
          label: 'Temperature',
          value: 0.7,
          min: 0,
          max: 2,
          defaultVal: 0.7,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('2.00'), findsOneWidget);
  });

  testWidgets('GenerationSectionCard titles and holds its children', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const GenerationSectionCard(
          title: 'Thinking',
          children: [Text('inside')],
        ),
      ),
    );
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('SliderSetting studioStyle preserves SliderSetting finder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SliderSetting(
          label: 'Context Size',
          value: 16384,
          min: 512,
          max: 131072,
          defaultVal: 16384,
          isInteger: true,
          studioStyle: true,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.widgetWithText(SliderSetting, 'Context Size'), findsOneWidget);
    expect(find.byType(StudioSliderCard), findsOneWidget);
  });

  testWidgets('ThinkingStrengthControl hides duplicate heading when false', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ThinkingStrengthControl(
          value: 'medium',
          thinkingOn: true,
          showHeading: false,
          onTurnOff: () {},
          onTurnOn: () {},
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Off'), findsOneWidget);
  });
}
