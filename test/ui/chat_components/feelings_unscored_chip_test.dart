// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply whose bond/trust judge could not be read shows one plain
// "not scored" chip, never "Bond unchanged · Trust unchanged". A scored zero
// still says "unchanged". The metadata shape is what
// test/services/chat/feelings_unscored_test.dart proves the real turn writes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kFeelingsUnscoredLabel, kFeelingsUnscoredMeta;
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

Future<void> _pump(WidgetTester tester, Map<String, dynamic> meta) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              text: 'She nods.',
              sender: 'Sophia',
              isUser: false,
              metadata: meta,
            ),
            index: 1,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed judge shows "not scored", not "unchanged"', (
    tester,
  ) async {
    // The live shape: the dance still stamps the carried mood and the needs
    // pass its deltas, which is what used to light "unchanged".
    await _pump(tester, {
      kFeelingsUnscoredMeta: true,
      'emotion_label': 'amusement',
      'needs_deltas': {
        'hunger': {'delta': -2, 'reason': 'walked to the porch'},
      },
    });
    expect(find.text(kFeelingsUnscoredLabel), findsOneWidget);
    expect(find.text('Bond unchanged'), findsNothing);
    expect(find.text('Trust unchanged'), findsNothing);
    expect(find.text('Mood: amusement'), findsOneWidget);
  });

  testWidgets('a scored zero still says unchanged', (tester) async {
    await _pump(tester, {
      'bond_delta': 0,
      'trust_delta': 0,
      'emotion_label': 'amusement',
    });
    expect(find.text('Bond unchanged'), findsOneWidget);
    expect(find.text('Trust unchanged'), findsOneWidget);
    expect(find.text(kFeelingsUnscoredLabel), findsNothing);
  });
}
