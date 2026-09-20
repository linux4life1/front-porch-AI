// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Spoken transcript no longer auto-scrolls (option B). The open Thought
// pane still has to follow new tokens unless the user scrolled it up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/bubbles/live_thought_body.dart';

Widget _app(Key key, String text) {
  return MaterialApp(
    home: Scaffold(
      body: LiveThoughtBody(key: key, text: text, followLatest: true),
    ),
  );
}

void main() {
  testWidgets('followLatest jumps to the newest think tokens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final key = GlobalKey();
    await tester.pumpWidget(_app(key, List.filled(8, 'line').join('\n')));
    await tester.pump();
    final controller = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('live-thought-scroll')),
        )
        .controller!;
    expect(controller.offset, 0);

    await tester.pumpWidget(
      _app(key, '${List.filled(40, 'later think token').join('\n')}\nTHE END'),
    );
    await tester.pump();
    await tester.pump();
    expect(
      controller.offset,
      greaterThan(0),
      reason: 'new think tokens must pull the pane to the end',
    );
  });

  testWidgets('a user scroll-up is not yanked back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final key = GlobalKey();
    var text = List.filled(40, 'token').join('\n');
    await tester.pumpWidget(_app(key, text));
    await tester.pump();
    await tester.pump();
    final controller = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('live-thought-scroll')),
        )
        .controller!;
    controller.jumpTo(0);
    await tester.pump();

    await tester.pumpWidget(_app(key, '$text\nmore'));
    await tester.pump();
    await tester.pump();
    expect(
      controller.offset,
      0,
      reason: 'option B inside the think pane: user scroll wins',
    );
  });
}
