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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/stage/transcript_auto_scroll.dart';

class _StackHost extends StatefulWidget {
  const _StackHost({super.key, required this.controller, this.listKey});

  final ScrollController controller;
  final Key? listKey;

  @override
  State<_StackHost> createState() => _StackHostState();
}

class _StackHostState extends State<_StackHost> {
  bool leading = false;
  double newestHeight = 40;

  void insertLeading() => setState(() => leading = true);

  void growNewest() => setState(() => newestHeight += 40);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: Stack(
            children: [
              if (leading) const SizedBox.shrink(),
              ListView(
                key: widget.listKey,
                controller: widget.controller,
                reverse: false,
                scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
                children: [
                  const SizedBox(height: 100, child: Text('OLDEST')),
                  const SizedBox(height: 100, child: Text('OLDER')),
                  const SizedBox(height: 100, child: Text('KEEP')),
                  SizedBox(height: newestHeight, child: const Text('LIVE')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('a leftover open pin is the gen chase (jumpTo newest)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _StackHost(controller: controller, listKey: GlobalKey()),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();
    final before = controller.offset;
    expect(pinTranscriptToLatest(controller), isTrue);
    await tester.pump();
    expect(controller.offset, isNot(before));
    expect(
      controller.offset,
      controller.position.maxScrollExtent,
      reason: 'pin during a stream tick is the forced follow; must stay gated',
    );
  });

  testWidgets('keyed list keeps offset and position across sibling insert', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    final listKey = GlobalKey();
    final host = GlobalKey<_StackHostState>();
    await tester.pumpWidget(
      _StackHost(key: host, controller: controller, listKey: listKey),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();
    final position = controller.position;

    host.currentState!.insertLeading();
    await tester.pump();
    expect(identical(controller.position, position), isTrue);
    expect(controller.offset, 80);
  });

  testWidgets('token-growth rebuilds do not re-anchor a scrolled-away list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    final listKey = GlobalKey();
    final host = GlobalKey<_StackHostState>();
    await tester.pumpWidget(
      _StackHost(key: host, controller: controller, listKey: listKey),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();
    final position = controller.position;

    for (var i = 0; i < 6; i++) {
      host.currentState!.growNewest();
      await tester.pump();
    }
    expect(identical(controller.position, position), isTrue);
    expect(
      controller.offset,
      80,
      reason: 'stream notify must not dispose the position or jumpTo(max)',
    );
  });

  test('chat wires a stable list key and lets the list own open/prepend', () {
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('_transcriptListKey'), isTrue);
    expect(page.contains('_scheduleOpenPin'), isFalse);
    final overlays = File(
      'lib/ui/pages/chat_page_overlays.dart',
    ).readAsStringSync();
    expect(overlays.contains('key: _transcriptListKey'), isTrue);
    expect(
      overlays.contains('sessionId: chatService.currentSessionId'),
      isTrue,
    );
    expect(overlays.contains('_scheduleOpenPin'), isFalse);
    final list = File(
      'lib/ui/chat_components/stage/chat_message_list.dart',
    ).readAsStringSync();
    expect(list.contains('ScrollCacheExtent.pixels(4000)'), isTrue);
    expect(list.contains('primary: false'), isTrue);
    expect(list.contains('findChildIndexCallback'), isTrue);
    expect(list.contains('_rowKey'), isTrue);
    expect(list.contains('nextTranscriptCenterIndex'), isTrue);
    expect(list.contains('CustomScrollView'), isTrue);
    expect(list.contains('TranscriptScrollController'), isFalse);
  });
}
