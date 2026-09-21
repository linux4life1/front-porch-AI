// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/stage/transcript_auto_scroll.dart';

class _GrowingTranscript extends StatefulWidget {
  const _GrowingTranscript({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_GrowingTranscript> createState() => _GrowingTranscriptState();
}

class _GrowingTranscriptState extends State<_GrowingTranscript> {
  double newestHeight = 40;

  void growTo(double height) => setState(() => newestHeight = height);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 400,
            height: 200,
            child: ListView(
              controller: widget.controller,
              reverse: false,
              children: [
                const SizedBox(height: 100, child: Text('OLDEST')),
                const SizedBox(height: 100, child: Text('OLDER')),
                const SizedBox(height: 100, child: Text('KEEP')),
                SizedBox(height: newestHeight, child: const Text('STREAM')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  test('classifyTranscriptGrowth splits open / prepend / other', () {
    expect(
      classifyTranscriptGrowth(
        sessionId: 's1',
        prevSession: null,
        prevLen: 0,
        prevTip: '',
        nextLen: 24,
        nextTip: 'Iris\u0000latest',
      ),
      TranscriptGrowth.open,
    );
    expect(
      classifyTranscriptGrowth(
        sessionId: 's1',
        prevSession: 's1',
        prevLen: 24,
        prevTip: 'Iris\u0000latest',
        nextLen: 224,
        nextTip: 'Iris\u0000latest',
      ),
      TranscriptGrowth.prepend,
    );
    expect(
      classifyTranscriptGrowth(
        sessionId: 's1',
        prevSession: 's1',
        prevLen: 224,
        prevTip: 'Iris\u0000latest',
        nextLen: 225,
        nextTip: 'Iris\u0000new reply',
      ),
      TranscriptGrowth.other,
    );
    expect(
      classifyTranscriptGrowth(
        sessionId: 's1',
        prevSession: 's1',
        prevLen: 224,
        prevTip: 'Iris\u0000latest',
        nextLen: 224,
        nextTip: 'Iris\u0000latest+',
      ),
      TranscriptGrowth.other,
    );
  });

  testWidgets('open/load pins a forward list to newest once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_GrowingTranscript(controller: controller));
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();
    expect(controller.offset, 80, reason: 'stale leftover from the last chat');

    expect(pinTranscriptToLatest(controller), isTrue);
    await tester.pump();
    expect(
      controller.offset,
      controller.position.maxScrollExtent,
      reason: 'open/load must land on the newest end (forward max)',
    );

    applyTranscriptAutoScroll(controller, generating: true);
    await tester.pump();
    expect(
      controller.offset,
      controller.position.maxScrollExtent,
      reason: 'stream helper must not move after the one-shot pin',
    );
  });

  testWidgets('idle user scroll is not rewritten by leftover hold plumbing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_GrowingTranscript(controller: controller));
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      controller.offset,
      80,
      reason:
          'applyContentDimensions hold would buck idle scrolling on every layout',
    );
  });

  testWidgets('stream growth does not chase a forward list sitting at latest', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final listKey = GlobalKey<_GrowingTranscriptState>();
    await tester.pumpWidget(
      _GrowingTranscript(key: listKey, controller: controller),
    );
    await tester.pump();
    expect(pinTranscriptToLatest(controller), isTrue);
    await tester.pump();
    final pinned = controller.offset;
    expect(pinned, controller.position.maxScrollExtent);

    listKey.currentState!.growTo(200);
    await tester.pump();
    expect(
      controller.offset,
      pinned,
      reason:
          'growing the newest bubble must leave offset put; jumping to the '
          'new max is the per-token chase',
    );
    expect(controller.position.maxScrollExtent, greaterThan(pinned));

    listKey.currentState!.growTo(280);
    await tester.pump();
    expect(
      controller.offset,
      pinned,
      reason: 'a second token batch must not accumulate a follow',
    );
  });

  testWidgets('scrolled-away offset is not rewritten on newest-end growth', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final listKey = GlobalKey<_GrowingTranscriptState>();
    await tester.pumpWidget(
      _GrowingTranscript(key: listKey, controller: controller),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();

    listKey.currentState!.growTo(160);
    await tester.pump();
    expect(
      controller.offset,
      80,
      reason:
          'stock forward list keeps pixels-from-top while the last row grows',
    );
  });

  test('chat page and bubble body honor the no-force-scroll contract', () {
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('TranscriptScrollController'), isFalse);
    expect(page.contains('resetHold'), isFalse);
    expect(page.contains('heldTranscriptOffset'), isFalse);
    expect(page.contains('_scheduleOpenPin'), isFalse);
    expect(page.contains('_transcriptListKey'), isTrue);
    expect(page.contains('pinTranscriptToLatest'), isFalse);
    expect(page.contains('keepScrollOffset: false'), isTrue);
    expect(page.contains('_scrollToBottom'), isFalse);
    final overlays = File(
      'lib/ui/pages/chat_page_overlays.dart',
    ).readAsStringSync();
    expect(
      overlays.contains('sessionId: chatService.currentSessionId'),
      isTrue,
    );
    expect(overlays.contains('_scheduleOpenPin'), isFalse);
    expect(overlays.contains('key: _transcriptListKey'), isTrue);
    final open = File(
      'lib/services/chat/chat_service_session_window.dart',
    ).readAsStringSync();
    expect(open.contains('getMessagesTailForSession'), isTrue);
    expect(open.contains('_prependOlderPage'), isTrue);
    expect(
      File(
        'lib/ui/chat_components/stage/transcript_scroll_controller.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/ui/chat_components/stage/transcript_auto_scroll.dart',
      ).readAsStringSync().contains('heldTranscriptOffset'),
      isFalse,
    );
    final list = File(
      'lib/ui/chat_components/stage/chat_message_list.dart',
    ).readAsStringSync();
    expect(
      list.contains('class ChatMessageList extends StatefulWidget'),
      isTrue,
    );
    expect(list.contains('reverse: false'), isTrue);
    expect(list.contains('applyTranscriptGrowth'), isTrue);
    expect(list.contains('TranscriptScrollController'), isFalse);
    final bubble = File(
      'lib/ui/chat_components/bubbles/message_bubble.content.dart',
    ).readAsStringSync();
    expect(bubble.contains('followLatest: false'), isTrue);
    expect(bubble.contains('followLatest: _followLiveThought'), isFalse);
    final selectable = File(
      'lib/ui/chat_components/bubbles/selectable_bubble_body.dart',
    ).readAsStringSync();
    expect(selectable.contains('NeverScrollableScrollPhysics'), isFalse);
    expect(selectable.contains('bubble-body-scroll-absorb'), isFalse);
    expect(selectable.contains('ListView'), isFalse);
    expect(selectable.contains('SelectionArea(child: child)'), isTrue);
    final jump = File(
      'lib/ui/chat_components/widgets/message_jump.dart',
    ).readAsStringSync();
    expect(jump.contains('axisDirection == AxisDirection.up'), isTrue);
  });
}
