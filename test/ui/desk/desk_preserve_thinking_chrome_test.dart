// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk.dart';

void main() {
  testWidgets('Harness has a Preserve thinking toggle', (tester) async {
    final session = DeskSession(
      folderRoot: '/tmp/throwaway-desk',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeskModeBar(
            mode: session.mode,
            onChanged: (m) => session.mode = m,
            preserveThinking: session.preserveThinking,
            onPreserveThinking: (v) => session.preserveThinking = v,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('desk-preserve-thinking')), findsOneWidget);
    expect(session.preserveThinking, isFalse);
    await tester.tap(find.byKey(const Key('desk-preserve-thinking')));
    await tester.pump();
    expect(session.preserveThinking, isTrue);
  });
}
