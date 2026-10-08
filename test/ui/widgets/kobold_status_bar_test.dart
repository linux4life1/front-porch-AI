// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The home screen's status bar for the local engine. It shows the status
// line, and a moving bar while something loads. It moved for every phase
// but "unloaded" and "ready", so a stopped engine with words on its status
// line (why it stopped, since 2026-10-05) would have looked as if it were
// still loading. Only starting and loading move it now.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  const why =
      'KoboldCpp ran out of graphics memory while loading the model. Try a '
      'smaller context size or a stronger cache compression.';

  Future<void> show(
    WidgetTester tester,
    KoboldPhase phase,
    String status,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KoboldStatusBar(status: status, phase: phase),
        ),
      ),
    );
  }

  Finder moving() => find.byType(LinearProgressIndicator);

  testWidgets('stopped with why: the words, and nothing moving', (
    tester,
  ) async {
    await show(tester, KoboldPhase.stopped, why);

    expect(find.text(why), findsOneWidget);
    expect(moving(), findsNothing);
  });

  testWidgets('starting or loading: the words and the moving bar', (
    tester,
  ) async {
    for (final phase in [KoboldPhase.starting, KoboldPhase.loading]) {
      await show(tester, phase, 'Loading model file...');

      expect(find.text('Loading model file...'), findsOneWidget);
      expect(moving(), findsOneWidget, reason: phase.name);
    }
  });

  testWidgets('ready with a note, or unloaded: words only, as before', (
    tester,
  ) async {
    for (final phase in [KoboldPhase.ready, KoboldPhase.unloaded]) {
      await show(tester, phase, 'A note.');

      expect(find.text('A note.'), findsOneWidget);
      expect(moving(), findsNothing, reason: phase.name);
    }
  });
}
