// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Backend-down / generation-error System banners are status, not story.
// They must not become `System: …` in the next prompt.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/chat_message.dart';

void main() {
  test('status banners are omitted from the generation history line', () {
    final msg = ChatMessage(
      text:
          'Backend is not running. Start it in Settings → Backend, '
          "or enable 'Auto-start on chat open'.",
      sender: 'System',
      isUser: false,
      metadata: const {kStatusBannerMeta: true},
    );
    expect(msg.isStatusBanner, isTrue);
    expect(msg.toPromptHistoryLine(), isEmpty);
  });

  test('ordinary System lines still reach the prompt', () {
    final msg = ChatMessage(
      text: 'Alex is Away / at work.',
      sender: 'System',
      isUser: false,
    );
    expect(msg.isStatusBanner, isFalse);
    expect(msg.toPromptHistoryLine(), 'System: Alex is Away / at work.');
  });
}
