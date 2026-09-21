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

void main() {
  test('older pages move the transcript center, not the scroll offset', () {
    expect(
      nextTranscriptCenterIndex(
        prevCenter: 0,
        kind: TranscriptGrowth.open,
        prevLen: 0,
        nextLen: 24,
      ),
      0,
    );
    expect(
      nextTranscriptCenterIndex(
        prevCenter: 0,
        kind: TranscriptGrowth.prepend,
        prevLen: 24,
        nextLen: 224,
      ),
      200,
    );
    expect(
      nextTranscriptCenterIndex(
        prevCenter: 200,
        kind: TranscriptGrowth.prepend,
        prevLen: 224,
        nextLen: 424,
      ),
      400,
    );
    expect(
      nextTranscriptCenterIndex(
        prevCenter: 200,
        kind: TranscriptGrowth.other,
        prevLen: 224,
        nextLen: 225,
      ),
      200,
    );
  });

  testWidgets('synthetic prepend hold adds the settled max delta', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: ListView(
              controller: controller,
              children: const [
                SizedBox(height: 300, child: Text('PAGE')),
                SizedBox(height: 100, child: Text('OLDEST')),
                SizedBox(height: 100, child: Text('OLDER')),
                SizedBox(height: 100, child: Text('KEEP')),
                SizedBox(height: 40, child: Text('LATEST')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();
    final max = controller.position.maxScrollExtent;
    holdTranscriptAfterPrepend(controller, max - 300);
    await tester.pump();
    expect(
      controller.offset,
      80 + 300,
      reason:
          'web / helper: add the settled growth. Desktop uses a center '
          'sliver instead so it never has to guess a stale max',
    );
  });

  test('desktop list anchors prepends at a center sliver, not a hold', () {
    final list = File(
      'lib/ui/chat_components/stage/chat_message_list.dart',
    ).readAsStringSync();
    expect(list.contains('CustomScrollView'), isTrue);
    expect(list.contains('transcript-center'), isTrue);
    expect(list.contains('nextTranscriptCenterIndex'), isTrue);
    expect(list.contains('holdTranscriptAfterPrepend'), isFalse);
    expect(list.contains('reverse: false'), isTrue);
    expect(list.contains('findChildIndexCallback'), isTrue);
  });
}
