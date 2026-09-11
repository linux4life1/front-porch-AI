// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';

void main() {
  test(
    'OpenCode 1.18 labels reasoning AND speech deltas field:text; part type decides',
    () {
      final parser = OpenCodeSseParser();
      final events = parser.add(
        'data: {"type":"message.part.updated","properties":{"sessionID":"ses_1","part":{"id":"prt_r","messageID":"msg_1","type":"reasoning","text":""}}}\n'
        '\n'
        'data: {"type":"message.part.delta","properties":{"sessionID":"ses_1","messageID":"msg_1","partID":"prt_r","field":"text","delta":"The user is asking"}}\n'
        '\n'
        'data: {"type":"message.part.updated","properties":{"sessionID":"ses_1","part":{"id":"prt_t","messageID":"msg_1","type":"text","text":""}}}\n'
        '\n'
        'data: {"type":"message.part.delta","properties":{"sessionID":"ses_1","messageID":"msg_1","partID":"prt_t","field":"text","delta":"Hmph."}}\n'
        '\n',
      );
      final deltas = events.whereType<OpenCodeTextDelta>().toList();
      expect(deltas, hasLength(2));
      expect(deltas[0].thinking, isTrue);
      expect(deltas[0].delta, 'The user is asking');
      expect(deltas[1].thinking, isFalse);
      expect(deltas[1].delta, 'Hmph.');
    },
  );

  test('text part.updated snapshot is not concatenated; only its delta is', () {
    final parser = OpenCodeSseParser();
    final events = parser.add(
      'data: {"type":"message.part.updated","properties":{"sessionID":"ses_1","delta":"Hi","part":{"id":"prt_t","type":"text","text":"Hi"}}}\n'
      '\n'
      'data: {"type":"message.part.updated","properties":{"sessionID":"ses_1","part":{"id":"prt_t","type":"text","text":"Hi there"}}}\n'
      '\n',
    );
    final deltas = events.whereType<OpenCodeTextDelta>().toList();
    expect(deltas, hasLength(1));
    expect(deltas.single.thinking, isFalse);
    expect(deltas.single.delta, 'Hi');
  });
}
