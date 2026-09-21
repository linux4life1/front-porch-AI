// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Saved RAG positions are persist indexes. Mapping them as list indexes
// into the ~24-row open window stamps old memories as "today".

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/rag_injection.dart';

ChatMessage _msg(String text, {int? day}) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: day == null
        ? null
        : {
            'realism_state': {'dayCount': day},
          },
  );
}

void main() {
  test('persist positions map through the open-window base', () {
    final window = [
      _msg('old morning', day: 3),
      _msg('later', day: 3),
      _msg('today dusk', day: 7),
    ];
    expect(
      storyDayAt(window, 100, 101, basePosition: 100),
      3,
      reason: 'persist 100 is window[0] Day 3, not the live tail',
    );
    expect(storyDayAt(window, 102, 102, basePosition: 100), 7);
  });
}
