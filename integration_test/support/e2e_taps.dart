// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'e2e_sandbox.dart';

/// Taps [finder] once its centre really hits it.
///
/// `pumpUntilFound` returns as soon as the widget is in the tree, which can
/// be while a pushed route is still fading in or a list is still laying out.
/// A plain `tester.tap` then lands on whatever is on top, prints a "would not
/// hit test" warning and carries on, and the test times out later on what
/// that tap should have done (a slow macOS runner, 2026-11-02:
/// layout_sweep_test's Create Group roster). Waiting for the widget to be
/// hit-testable at its centre turns that into a tap that cannot miss.
Future<void> tapWhenHittable(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final hittable = finder.hitTestable();
  await pumpUntilFound(tester, hittable, timeout: timeout);
  await tester.tap(hittable.first);
}
