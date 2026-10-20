// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Layout + unit regression guard for the custom climate editor.
//
// Field report 2026-07-29: the "°F shown" caption overflowed the season
// cards by 11px, and the blocking warnings said "set a display °C" while
// every temperature on screen was °F. This test pins, with the real Roboto
// metrics the harness loads:
//   * zero layout overflow at the dialog's spec size, °C and °F modes;
//   * the anchor caption is FULLY visible (not faded/clipped);
//   * every temperature string follows the active display unit.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/worlds/climate_editor_dialog.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Volcanic draft matching the report: Winter=Inferno, Spring=Warm,
/// Summer=Hot, Autumn=Mild — winter and summer can reach extremes, so both
/// render anchor inputs ("N° shown"); the other two render "auto".
final String _volcanicJson = jsonEncode({
  'id': 'custom',
  'displayName': 'Mars — Chryse Planitia',
  'description': 'Test climate',
  'weights': {
    'winter': [70, 18, 6, 2, 3, 1, 0],
    'spring': [75, 15, 5, 1, 3, 1, 0],
    'summer': [80, 12, 4, 0, 2, 2, 0],
    'autumn': [72, 16, 6, 2, 3, 1, 0],
  },
  'baseTemp': {'winter': 7, 'spring': 3, 'summer': 4, 'autumn': 2},
  'bandRange': [1, 6],
  'displayAnchorsC': {'winter': 600, 'summer': 200},
  'diurnalAmplitude': 2.2,
  'conditionSkin': {
    'storm': {
      'label': 'Planet-Wide Dust Storm',
      'emoji': '🟠',
      'stance': 'dangerous',
      'flavour': 'the sky goes ochre for weeks',
    },
  },
});

Future<void> _openEditor(
  WidgetTester tester, {
  required bool fahrenheit,
  required Size window,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showClimateEditorDialog(
                context,
                worldName: 'Mars — Chryse Planitia',
                existingBiomeJson: _volcanicJson,
                fahrenheit: fahrenheit,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The caption must render at its full intrinsic width — a faded/clipped
/// "°F sh…" passes an overflow check but fails the maintainer.
void _expectFullyVisible(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(
    find.textContaining(text).first,
  );
  expect(
    p.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(p.size.width + 0.01),
    reason:
        '"$text" is clipped: needs '
        '${p.getMaxIntrinsicWidth(double.infinity)}px, got ${p.size.width}px',
  );
}

void main() {
  testWidgets('renders °C by default with no overflow at spec size', (
    tester,
  ) async {
    await _openEditor(tester, fahrenheit: false, window: const Size(1280, 820));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('°C shown'), findsWidgets);
    expect(find.textContaining('°F shown'), findsNothing);
    _expectFullyVisible(tester, '°C shown');
  });

  testWidgets('°F mode: captions, anchors, and warnings all speak °F', (
    tester,
  ) async {
    await _openEditor(tester, fahrenheit: true, window: const Size(1280, 820));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('°F shown'), findsWidgets);
    expect(find.textContaining('°C shown'), findsNothing);
    _expectFullyVisible(tester, '°F shown');

    // Winter's anchor is stored as 600 °C and must arrive as 1112 °F.
    final winterAnchor = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '1112',
    );
    expect(winterAnchor, findsOneWidget);

    // Clearing it raises the blocking warning — worded in the display unit
    // (validate() speaks canonical °C; the dialog translates).
    await tester.enterText(winterAnchor, '');
    await tester.pumpAndSettle();
    expect(find.textContaining('set a display °F'), findsWidgets);
    expect(find.textContaining('set a display °C'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at a smaller window', (tester) async {
    await _openEditor(tester, fahrenheit: true, window: const Size(1024, 720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('light mode: each blocker shows once and every line reads', (
    tester,
  ) async {
    // Tall enough that the preview column builds every row, so a repeated
    // blocker below the fold would still be counted.
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showClimateEditorDialog(
                  context,
                  worldName: 'Mars — Chryse Planitia',
                  existingBiomeJson: _volcanicJson,
                  fahrenheit: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final palette = AppThemePalettes.porch.light;

    // A blocker the preview also noticed is listed once, in °F.
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '1112',
      ),
      '',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('set a display °F'), findsOneWidget);
    expect(find.textContaining('set a display °C'), findsNothing);

    // A rename with no danger level is the column's own blocker.
    final cloudy = find.textContaining('Cloudy →');
    await tester.scrollUntilVisible(
      cloudy,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find
          .byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == 'rename (e.g. Dust Squall)',
          )
          .first,
      'Glare',
    );
    await tester.pumpAndSettle();
    final blocker = find.textContaining('characters would picnic in it');
    await tester.scrollUntilVisible(
      blocker,
      200,
      scrollable: find
          .ancestor(
            of: find.text('Refresh preview'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(blocker, findsOneWidget);

    double readsAt(Finder f, Color ground) {
      final p = tester.renderObject<RenderParagraph>(f);
      final ink = p.text.style!.color!;
      return contrastRatio(Color.alphaBlend(ink, ground), ground);
    }

    expect(readsAt(blocker, palette.background), greaterThanOrEqualTo(4.5));
    expect(
      readsAt(cloudy, palette.surfaceContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });
}
