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
              reverse: true,
              children: [
                SizedBox(height: newestHeight, child: const Text('STREAM')),
                const SizedBox(height: 100, child: Text('KEEP')),
                const SizedBox(height: 100, child: Text('OLDER')),
                const SizedBox(height: 100, child: Text('OLDEST')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('stream growth does not rewrite a stock reverse-list offset', (
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
    expect(controller.offset, 0);

    listKey.currentState!.growTo(200);
    await tester.pump();
    expect(
      controller.offset,
      0,
      reason: 'hold/correctPixels would push offset off 0 and jitter the page',
    );

    listKey.currentState!.growTo(280);
    await tester.pump();
    expect(
      controller.offset,
      0,
      reason: 'a second growth must not accumulate a rewritten offset',
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
      reason: 'hold added growth to pixels and fought Flutter; stock keeps 80',
    );
  });

  test('chat page and bubble body honor the no-force-scroll contract', () {
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('TranscriptScrollController'), isFalse);
    expect(page.contains('resetHold'), isFalse);
    expect(page.contains('heldTranscriptOffset'), isFalse);
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
      list.contains('class ChatMessageList extends StatelessWidget'),
      isTrue,
    );
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
  });
}
