// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Reading Size 1.4 cut the app sidebar's labels short ("Create Charac…",
// "AI Character …") because the sidebar stayed 250 px wide while its text
// grew. It now widens with the text so every label fits, up to the largest
// Reading Size, and stays 250 px at ordinary sizes.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/theme/reading_size.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

/// The app's text scale: window width over 1280 (0.85 to 1.5) times the
/// Reading Size, as main.dart applies it.
double _appScale(double windowWidth, double readingSize) =>
    (windowWidth / 1280).clamp(0.85, 1.5) * readingSize;

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required Size window,
  required double scale,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(
          value: FakeAppState(selectedIndex: 3),
        ),
        ChangeNotifierProvider<UpdateService>.value(value: FakeUpdateService()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: Row(
                children: [
                  Sidebar(),
                  Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectEveryLabelWhole(WidgetTester tester) {
  // The width is measured from Sidebar.labels: a row added to the menu but
  // not to that list would not be measured, so the two must match.
  final rendered = tester
      .widgetList<Text>(
        find.descendant(
          of: find.descendant(
            of: find.byType(Sidebar),
            matching: find.byType(SingleChildScrollView),
          ),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data)
      .toList();
  expect(rendered, Sidebar.labels, reason: 'nav rows and Sidebar.labels');

  for (final label in Sidebar.labels) {
    final text = find.descendant(
      of: find.byType(Sidebar),
      matching: find.text(label),
    );
    expect(text, findsOneWidget, reason: '"$label" is not in the sidebar');
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$label" is cut short',
    );
  }
}

void main() {
  setupPathProviderMock();

  testWidgets('ordinary sizes keep the 250 px sidebar', (tester) async {
    await _pumpSidebar(
      tester,
      window: const Size(1440, 900),
      scale: _appScale(1440, 1.0),
    );
    expect(tester.getSize(find.byType(Sidebar)).width, kSidebarWidth);
    _expectEveryLabelWhole(tester);
  });

  for (final reading in [1.4, kReadingScaleMax]) {
    testWidgets('Reading Size $reading: every label fits', (tester) async {
      await _pumpSidebar(
        tester,
        window: const Size(1440, 900),
        scale: _appScale(1440, reading),
      );
      _expectEveryLabelWhole(tester);
      expect(
        tester.getSize(find.byType(Sidebar)).width,
        greaterThan(kSidebarWidth),
      );
    });
  }
}
