// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Scrolling up through a long chat mounts older rows above the reader.
// The rows already on screen must move only by the wheel, never jump
// down a few bubbles when a page lands — with or without a Thought
// opened along the way. Reading a Thought (opening it, scrolling inside
// its own box) must not move the chat at all.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

const _step = 120.0;

ChatMessage _msg(int i) => i.isOdd
    ? (ChatMessage(
        text:
            '<think>${'plan ' * 600}</think>\n'
            'line $i ${'word ' * (5 + (i * 37) % 300)}',
        sender: 'Iris',
        isUser: false,
      )..thinkingDurationMs = 1200)
    : ChatMessage(text: 'line $i ${'word ' * 20}', sender: 'You', isUser: true);

(File?, Color?) _noSpeaker(ChatMessage _) => (null, null);

Map<int, double> _rowTops(WidgetTester tester) => {
  for (final e in find.byType(MessageBubble).evaluate())
    (e.widget as MessageBubble).index: tester
        .getRect(find.byWidget(e.widget))
        .top,
};

/// Wheel to the top, failing if any row seen in two frames moved by
/// more than one wheel step (or upward).
Future<int> _wheelToTop(
  WidgetTester tester,
  ScrollController c, {
  bool openThought = false,
}) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(find.byType(ListView))),
  );
  var reveals = 0;
  var opened = false;
  var before = _rowTops(tester);
  for (var i = 0; i < 600; i++) {
    final rowsBefore = find.byType(MessageBubble).evaluate().length;
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -_step)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final after = _rowTops(tester);
    for (final entry in after.entries) {
      final was = before[entry.key];
      if (was == null || was > 700 || was < -200) continue;
      final moved = entry.value - was;
      expect(
        moved,
        inInclusiveRange(-0.5, _step + 0.5),
        reason: 'row ${entry.key} jumped by $moved at wheel $i',
      );
    }
    if (find.byType(MessageBubble).evaluate().length > rowsBefore) reveals++;
    if (openThought && !opened && i == 20) {
      final toggle = find.byKey(const Key('thought-toggle')).evaluate().where((
        e,
      ) {
        final y = tester.getCenter(find.byWidget(e.widget)).dy;
        return y > 50 && y < 650;
      });
      if (toggle.isNotEmpty) {
        await tester.tap(find.byWidget(toggle.first.widget));
        await tester.pump();
        opened = true;
      }
    }
    before = _rowTops(tester);
    if (c.offset <= 0 && before.containsKey(0)) break;
  }
  if (openThought) expect(opened, isTrue);
  return reveals;
}

Future<ScrollController> _pump(
  WidgetTester tester,
  List<ChatMessage> messages,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = ScrollController(keepScrollOffset: false);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatMessageList(
          sessionId: 's1',
          messages: messages,
          controller: c,
          resolveSpeaker: _noSpeaker,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('revealing older rows keeps the reader in place', (tester) async {
    final c = await _pump(tester, [for (var i = 0; i < 120; i++) _msg(i)]);
    expect(await _wheelToTop(tester, c), greaterThanOrEqualTo(3));
  });

  testWidgets('an opened Thought does not throw the next reveal off', (
    tester,
  ) async {
    final c = await _pump(tester, [for (var i = 0; i < 120; i++) _msg(i)]);
    expect(await _wheelToTop(tester, c, openThought: true), greaterThan(0));
  });

  testWidgets('opening the latest Thought right after open stays put', (
    tester,
  ) async {
    final c = await _pump(tester, [for (var i = 0; i < 60; i++) _msg(i)]);
    final before = c.offset;
    await tester.tap(find.byKey(const Key('thought-toggle')).last);
    await tester.pumpAndSettle();
    expect(c.offset, closeTo(before, 0.5));
  });

  testWidgets('scrolling inside a Thought box does not page older rows', (
    tester,
  ) async {
    final c = await _pump(tester, [for (var i = 0; i < 60; i++) _msg(i)]);
    await tester.tap(find.byKey(const Key('thought-toggle')).last);
    await tester.pumpAndSettle();
    final rows = find.byType(MessageBubble).evaluate().length;
    final before = c.offset;
    final box = find.byKey(const Key('live-thought-scroll')).last;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(box)));
    final inner = tester.widget<SingleChildScrollView>(box).controller!;
    // The box opens on its last line; wheel up to its own top, which is
    // inside the 64px "reached the top" band.
    expect(inner.offset, greaterThan(64));
    while (inner.offset > 0) {
      final was = inner.offset;
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
      await tester.pumpAndSettle();
      expect(inner.offset, lessThan(was), reason: 'wheel reached the box');
    }
    expect(find.byType(MessageBubble).evaluate().length, rows);
    expect(c.offset, closeTo(before, 0.5));
  });
}
