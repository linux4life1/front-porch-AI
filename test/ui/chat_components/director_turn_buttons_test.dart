// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Director Mode's Play/Pause must not move when auto-chat starts. The input
// row is right-aligned behind an expanding text field, so when Next Character
// vanished during auto-chat everything to its left slid one slot right and
// Impersonate landed under the spot where Play had been: the click meant to
// pause fired Impersonate instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

void main() {
  testWidgets('Pause sits exactly where Play was and the same click pauses', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var autoPlay = false;
    var impersonations = 0;
    var nextTurns = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(child: TextField()),
                // Same shape as the chat input row: wand, turn buttons, send.
                IconButton(
                  tooltip: 'Impersonate',
                  icon: const Icon(Icons.auto_fix_high),
                  onPressed: () => impersonations++,
                ),
                DirectorTurnButtons(
                  showAutoPlay: true,
                  autoPlayActive: autoPlay,
                  nextTooltip: 'Trigger next character',
                  onToggleAutoPlay: () => setState(() => autoPlay = !autoPlay),
                  onNextCharacter: () => nextTurns++,
                  playColor: Colors.amber,
                  pauseColor: Colors.orange,
                  nextColor: Colors.purple,
                ),
                IconButton(
                  icon: const Icon(Icons.movie_creation),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final play = find.byIcon(Icons.play_circle_filled);
    expect(play, findsOneWidget);
    final playRect = tester.getRect(play);

    await tester.tapAt(playRect.center);
    await tester.pump();
    expect(autoPlay, isTrue, reason: 'the Play tap must start auto-chat');

    final pause = find.byIcon(Icons.pause_circle_filled);
    expect(pause, findsOneWidget);
    expect(
      tester.getRect(pause),
      playRect,
      reason: 'Pause must occupy exactly the slot Play had',
    );
    expect(
      find.byIcon(Icons.group),
      findsOneWidget,
      reason: 'Next Character keeps its slot while auto-chat runs',
    );

    // Greyed out while auto-chat picks the speaker.
    await tester.tap(find.byIcon(Icons.group));
    await tester.pump();
    expect(nextTurns, 0);

    // The same spot now pauses; it must not reach Impersonate.
    await tester.tapAt(playRect.center);
    await tester.pump();
    expect(autoPlay, isFalse, reason: 'the second click must pause');
    expect(impersonations, 0, reason: 'Impersonate must never fire here');
    expect(tester.getRect(find.byIcon(Icons.play_circle_filled)), playRect);

    await tester.tap(find.byIcon(Icons.group));
    await tester.pump();
    expect(nextTurns, 1, reason: 'Next Character works again once paused');
  });
}
