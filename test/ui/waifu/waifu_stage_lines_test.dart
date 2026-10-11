// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  Future<void> pumpTranscript(WidgetTester tester, WaifuSession session) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaifuTranscript(session: session, coworker: 'Mira'),
          ),
        ),
      );

  testWidgets('a stage row is centred narration, not a bubble', (tester) async {
    final session = WaifuSession(
      folderRoot: '.',
      coworker: CharacterCard(name: 'Mira'),
      transcript: [
        const WaifuMessage.user('build it'),
        const WaifuMessage.assistant('On it.'),
        const WaifuMessage.stage('Mira hit a snag.', detail: 'HTTP 500'),
      ],
    );
    await pumpTranscript(tester, session);

    final line = find.text('Mira hit a snag.');
    expect(line, findsOneWidget);
    final width = tester.getSize(find.byType(Scaffold)).width;
    expect(tester.getCenter(line).dx, moreOrLessEquals(width / 2, epsilon: 24));
    expect(tester.widget<Text>(line).style?.fontStyle, FontStyle.italic);
    expect(find.text('HTTP 500'), findsNothing);

    await tester.tap(find.byKey(const Key('waifu-stage-toggle')));
    await tester.pump();
    expect(find.text('HTTP 500'), findsOneWidget);
  });

  testWidgets('a stage row right after the user line still shows', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '.',
      coworker: CharacterCard(name: 'Mira'),
      transcript: [
        const WaifuMessage.user('build it'),
        const WaifuMessage.stage('Mira sets the keyboard down.'),
      ],
    );
    await pumpTranscript(tester, session);
    expect(find.text('Mira sets the keyboard down.'), findsOneWidget);
    expect(find.byKey(const Key('waifu-stage-toggle')), findsNothing);
  });
}
