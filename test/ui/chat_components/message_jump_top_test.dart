// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A receipt tap must land on the START of the cited message. Centering a
// message taller than the view showed its middle and cut its opening off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/widgets/message_jump.dart';

void main() {
  testWidgets('a tall cited message lands with its top in view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messages = [
      for (var i = 0; i < 40; i++)
        ChatMessage(text: 'line $i', sender: 'Iris', isUser: false),
    ];
    final keys = <ChatMessage, GlobalKey>{};
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: messages.length,
            itemBuilder: (context, i) => SizedBox(
              key: keys.putIfAbsent(messages[i], GlobalKey.new),
              // The cited one is taller than the whole view.
              height: i == 12 ? 1500 : 80.0 + (i % 5) * 25,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(messages[i].text),
              ),
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final target = messages[12];
    var done = false;
    jumpToMessage(
      controller: controller,
      messages: messages,
      target: target,
      keyOf: (m) => keys[m],
    ).then((_) => done = true);
    for (var i = 0; i < 60 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(done, isTrue);
    final top = tester.getTopLeft(find.byKey(keys[target]!)).dy;
    expect(top, closeTo(0, 1));
    expect(find.text('line 12'), findsOneWidget);
  });
}
