// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

void main() {
  test('empty-result fragment tells the character not to invent', () {
    expect(mcpEmptyResultFragment(), contains('Do not invent'));
    expect(mcpEmptyResultFragment(), contains("don't know"));
    expect(mcpEmptyResultFragment(), isNot(contains('{')));
  });

  test('result fragment wraps data; raw JSON is not the bubble text', () {
    final text = mcpResultFragment('{"containers":["web"]}');
    expect(text, contains('UNTRUSTED EXTERNAL TOOL DATA'));
    expect(text, contains('containers'));
    expect(text, contains('React as yourself'));
    expect(kMcpCharacterLine, contains("Don't recite the JSON"));
    expect(kMcpCharacterLine, contains("Don't break character"));
  });

  test('decision cue is a silent check, not the reply', () {
    expect(kMcpDecisionCue, contains('silent tool-use check'));
    expect(mcpDecisionPrompt('Hello'), contains(kMcpDecisionCue));
  });
}
