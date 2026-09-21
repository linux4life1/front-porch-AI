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
  test('classify treats a longer list with the same tip as prepend', () {
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
  });

  testWidgets('prepend helper adds a settled max delta once', (tester) async {
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
              reverse: false,
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
    applyTranscriptGrowth(
      controller,
      pending: TranscriptGrowth.prepend,
      previousMax: max - 300,
    );
    await tester.pump();
    expect(
      controller.offset,
      80 + 300,
      reason:
          'one-shot prepend adjust uses a settled max, not a children-list '
          'rebuild (those report a stale max for a frame)',
    );

    applyTranscriptAutoScroll(controller, generating: true);
    await tester.pump();
    expect(controller.offset, 80 + 300);
  });

  test('desktop list stays the Mac-pass forward ListView', () {
    final list = File(
      'lib/ui/chat_components/stage/chat_message_list.dart',
    ).readAsStringSync();
    expect(list.contains('ListView.builder'), isTrue);
    expect(list.contains('reverse: false'), isTrue);
    expect(list.contains('CustomScrollView'), isFalse);
    expect(list.contains('transcript-center'), isFalse);
    expect(list.contains('applyTranscriptGrowth'), isTrue);
    expect(list.contains('TranscriptScrollController'), isFalse);
    expect(
      File(
        'lib/ui/chat_components/stage/transcript_auto_scroll.dart',
      ).readAsStringSync().contains('heldTranscriptOffset'),
      isFalse,
    );
  });
}
