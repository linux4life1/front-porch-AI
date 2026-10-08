// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Opening a chat must land on the latest line even when a row grows after
// the first pin (an image decoding, a font arriving). A reader who has
// already scrolled away must not be yanked back down.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

/// Stand-in for an image decode: zero height, then the real height.
class _LateGrow extends StatefulWidget {
  const _LateGrow({required this.delay, required this.height});
  final Duration delay;
  final double height;

  @override
  State<_LateGrow> createState() => _LateGrowState();
}

class _LateGrowState extends State<_LateGrow> {
  double h = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => h = widget.height);
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(height: h);
}

List<ChatMessage> _msgs(int n) => [
  for (var i = 0; i < n; i++)
    ChatMessage(
      text: 'line $i ${'word ' * (5 + (i * 37) % 120)}',
      sender: i.isEven ? 'You' : 'Iris',
      isUser: i.isEven,
    ),
];

(File?, Color?) _noSpeaker(ChatMessage _) => (null, null);

Future<ScrollController> _open(
  WidgetTester tester, {
  Set<int> lateRows = const {},
  Duration delay = const Duration(milliseconds: 120),
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = ScrollController(keepScrollOffset: false);
  addTearDown(controller.dispose);
  final messages = _msgs(40);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageList(
          sessionId: 's1',
          messages: messages,
          controller: controller,
          resolveSpeaker: _noSpeaker,
          belowBubble: (m, i) => lateRows.contains(i)
              ? _LateGrow(delay: delay, height: 320)
              : null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(delay + const Duration(milliseconds: 16));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('control: no late content lands on latest', (tester) async {
    final c = await _open(tester);
    expect(c.offset, closeTo(c.position.maxScrollExtent, 1));
  });

  testWidgets('late image height in the tail still lands on latest', (
    tester,
  ) async {
    final c = await _open(tester, lateRows: {37, 39});
    expect(c.offset, closeTo(c.position.maxScrollExtent, 1));
  });

  testWidgets('late growth on the next frame is absorbed', (tester) async {
    final c = await _open(tester, lateRows: {37, 39}, delay: Duration.zero);
    expect(c.offset, closeTo(c.position.maxScrollExtent, 1));
  });

  testWidgets('late growth above the viewport still lands on latest', (
    tester,
  ) async {
    final c = await _open(tester, lateRows: {33});
    expect(c.offset, closeTo(c.position.maxScrollExtent, 1));
  });

  testWidgets('user scroll during hold is respected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            sessionId: 's1',
            messages: _msgs(40),
            controller: controller,
            resolveSpeaker: _noSpeaker,
            belowBubble: (m, i) => i == 39
                ? const _LateGrow(delay: Duration(seconds: 1), height: 320)
                : null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    final userOffset = controller.offset;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(userOffset, 1));
  });
}
