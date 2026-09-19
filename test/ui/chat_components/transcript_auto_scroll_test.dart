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
  testWidgets('applyTranscriptAutoScroll leaves a user-owned offset alone', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          reverse: true,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
        ),
      ),
    );
    controller.jumpTo(240);
    await tester.pump();
    expect(controller.offset, 240);

    applyTranscriptAutoScroll(controller, generating: true);
    applyTranscriptAutoScroll(controller, generating: false);
    await tester.pump();
    expect(
      controller.offset,
      240,
      reason: 'option B: send/stream must not jumpTo(0)',
    );
  });

  test('send and ChatPage no longer pin the transcript', () {
    final input = File('lib/ui/pages/chat_page.input.dart').readAsStringSync();
    expect(input.contains('_scrollToBottom'), isFalse);
    final page = File('lib/ui/pages/chat_page.dart').readAsStringSync();
    expect(page.contains('void _scrollToBottom'), isFalse);
    expect(page.contains('bool _autoScroll'), isFalse);
  });
}
