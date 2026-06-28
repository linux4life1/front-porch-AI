// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Shared widget-golden harness. Every widget golden renders through
// [expectThemedGoldens] so the suite scales: one deterministic surface, the
// bundled Roboto font (see flutter_test_config.dart), and both light + dark
// themes captured so the mandated AppColors system is locked in both modes.
//
// PNGs are written relative to the calling test file under
// `_goldens/<group>/<name>.<light|dark>.png` (i.e. test/golden/widget/_goldens/).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _rootKey = Key('golden-root');

/// Pump [child] in a deterministic MaterialApp for the given [brightness] and
/// [surface] size, then settle.
///
/// Set [settle] to false for screens that own a perpetual ticker (e.g. a focused
/// text field's blinking cursor): `pumpAndSettle` would never return, so we pump
/// a couple of bounded frames instead — enough to lay out a static golden.
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
  required Size surface,
  bool settle = true,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: RepaintBoundary(
        key: _rootKey,
        child: Scaffold(
          body: Center(child: Padding(padding: const EdgeInsets.all(12), child: child)),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Fully decode any mounted images before the golden is captured. `pumpAndSettle`
  // does NOT await real async image-decode frames, so a golden that renders
  // `Image.asset`/`Image.file` thumbnails (e.g. the background picker grid)
  // would otherwise snapshot whatever decode stage it happened to reach — making
  // that golden flaky (the symptom: a light/dark pair where one variant captures
  // the decoded art and the other captures blanks). Precaching makes it stable.
  await _precacheMountedImages(tester);
  await tester.pump();
}

/// Synchronously force every [Image] currently in the tree to finish decoding so
/// image-heavy goldens are deterministic. No-op when the tree has no images.
/// Unresolved providers (e.g. `Image.network`, which fails under flutter_test)
/// are swallowed so they never hang or throw the capture.
Future<void> _precacheMountedImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element, onError: (_, _) {});
    }
  });
}

/// Render [child] in both light and dark themes and assert each against its
/// committed PNG golden. Refresh intentional UI changes with
/// `flutter test --tags golden --update-goldens` on the Linux/CI image.
///
/// For tests that navigate a [StatefulWidget] via [afterPump], pass
/// [childBuilder] instead of [child]: it is called once per brightness so each
/// pass gets a fresh widget instance (and therefore a fresh [State]).  Using a
/// plain [child] would reuse the same [State] across both passes, leaving
/// `_currentStep` or similar fields set to the value from the previous pass.
Future<void> expectThemedGoldens(
  WidgetTester tester, {
  Widget? child,
  Widget Function()? childBuilder,
  required String group,
  required String name,
  Size surface = const Size(420, 220),
  bool settle = true,
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  assert(
    child != null || childBuilder != null,
    'Provide either child or childBuilder.',
  );
  for (final brightness in Brightness.values) {
    final mode = brightness == Brightness.light ? 'light' : 'dark';
    await pumpGolden(
      tester,
      childBuilder != null ? childBuilder() : child!,
      brightness: brightness,
      surface: surface,
      settle: settle,
    );
    // Optional interaction (e.g. expand a collapsible section) before capture.
    if (afterPump != null) {
      await afterPump(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('_goldens/$group/$name.$mode.png'),
    );
  }
}
