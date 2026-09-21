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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/stage/transcript_auto_scroll.dart';

/// Reverse transcript: children[0] is newest. Extra older rows go at the
/// far end — the same direction as `getMessagesBeforePosition` prepend.
class _PagingTranscript extends StatefulWidget {
  const _PagingTranscript({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_PagingTranscript> createState() => _PagingTranscriptState();
}

class _PagingTranscriptState extends State<_PagingTranscript> {
  int olderPages = 0;

  void prependOlderPage() => setState(() => olderPages++);

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
                const SizedBox(height: 40, child: Text('LATEST')),
                const SizedBox(height: 100, child: Text('KEEP')),
                const SizedBox(height: 100, child: Text('OLDER')),
                const SizedBox(height: 100, child: Text('OLDEST')),
                for (var i = 0; i < olderPages; i++)
                  SizedBox(height: 300, child: Text('PAGE-$i')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('open stays on latest when older pages prepend', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    final listKey = GlobalKey<_PagingTranscriptState>();
    await tester.pumpWidget(
      _PagingTranscript(key: listKey, controller: controller),
    );
    await tester.pump();
    expect(pinTranscriptToLatest(controller), isTrue);
    await tester.pump();
    expect(controller.offset, 0);

    listKey.currentState!.prependOlderPage();
    await tester.pump();
    listKey.currentState!.prependOlderPage();
    await tester.pump();
    expect(
      controller.offset,
      0,
      reason:
          'stock reverse list keeps newest at 0; hold would add each page '
          'to offset and walk off latest',
    );
  });

  testWidgets('scrolled-away offset survives a backward prepend', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final listKey = GlobalKey<_PagingTranscriptState>();
    await tester.pumpWidget(
      _PagingTranscript(key: listKey, controller: controller),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();

    listKey.currentState!.prependOlderPage();
    await tester.pump();
    expect(
      controller.offset,
      80,
      reason:
          'older rows grow maxScrollExtent; stock keeps pixels-from-newest. '
          'hold added that growth and jumped the page',
    );
  });
}
