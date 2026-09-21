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
import 'package:front_porch_ai/ui/chat_components/stage/transcript_scroll_controller.dart';

Widget _reverseList({
  required ScrollController controller,
  required double newestHeight,
}) {
  return MaterialApp(
    home: SizedBox(
      height: 200,
      child: ListView(
        controller: controller,
        reverse: true,
        children: [
          SizedBox(height: newestHeight, child: const Text('STREAM')),
          const SizedBox(height: 100, child: Text('KEEP')),
          const SizedBox(height: 100, child: Text('OLDER')),
          const SizedBox(height: 100, child: Text('OLDEST')),
        ],
      ),
    ),
  );
}

void main() {
  test('heldTranscriptOffset keeps rows still when the newest end grows', () {
    expect(
      heldTranscriptOffset(
        offset: 0,
        previousMax: 400,
        newMax: 480,
        minExtent: 0,
      ),
      80,
      reason: 'already at newest: growth must not pin to the new bottom',
    );
    expect(
      heldTranscriptOffset(
        offset: 240,
        previousMax: 400,
        newMax: 480,
        minExtent: 0,
      ),
      320,
      reason: 'scrolled away: growth must not yank toward the new bottom',
    );
    expect(
      heldTranscriptOffset(
        offset: 240,
        previousMax: 400,
        newMax: 400,
        minExtent: 0,
      ),
      240,
    );
  });

  testWidgets('stream growth at newest does not pin offset 0', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TranscriptScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _reverseList(controller: controller, newestHeight: 40),
    );
    await tester.pump();
    expect(controller.offset, 0);

    await tester.pumpWidget(
      _reverseList(controller: controller, newestHeight: 200),
    );
    await tester.pump();
    expect(
      controller.offset,
      greaterThan(0),
      reason:
          'growing the live bubble must not keep offset 0 (stick-to-bottom)',
    );
    expect(find.text('KEEP'), findsOneWidget);
  });

  testWidgets('scrolled-away offset is not yanked toward the new bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = TranscriptScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _reverseList(controller: controller, newestHeight: 40),
    );
    await tester.pump();
    controller.jumpTo(80);
    await tester.pump();

    await tester.pumpWidget(
      _reverseList(controller: controller, newestHeight: 160),
    );
    await tester.pump();
    expect(
      controller.offset,
      greaterThan(80),
      reason:
          'growth + preserved pixels-from-bottom is the yank; hold adds growth',
    );
  });

  test('chat page and bubble body honor the no-force-scroll contract', () {
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('TranscriptScrollController'), isTrue);
    final bubble = File(
      'lib/ui/chat_components/bubbles/message_bubble.content.dart',
    ).readAsStringSync();
    expect(bubble.contains('followLatest: false'), isTrue);
    expect(bubble.contains('followLatest: _followLiveThought'), isFalse);
    final selectable = File(
      'lib/ui/chat_components/bubbles/selectable_bubble_body.dart',
    ).readAsStringSync();
    expect(selectable.contains('NeverScrollableScrollPhysics'), isTrue);
    expect(selectable.contains('bubble-body-scroll-absorb'), isTrue);
  });
}
