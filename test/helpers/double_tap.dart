// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

/// Taps [button] twice with no frame between, the way a fast double click
/// lands: the second tap runs the handler the first build handed out,
/// before a `busy` flag can rebuild the button disabled. Every create or
/// save button gets this in its test, followed by an assert that exactly
/// one write happened (CLAUDE.md, "Definition of done").
Future<void> doubleTapNoFrame(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.tap(button, warnIfMissed: false);
}
