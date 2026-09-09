// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

void main() {
  const tools = [
    {
      'type': 'function',
      'function': {'name': 'write'},
    },
  ];

  test('required sentinel starts at required, not a named function', () {
    final probe = ToolChoiceStyleProbe();
    expect(
      probe.startingStyleFor('waifu|x|', toolChoice: kToolChoiceRequired),
      ToolChoiceStyle.required,
    );
    expect(
      probe.startingStyleFor('waifu|x|', toolChoice: 'write'),
      ToolChoiceStyle.named,
    );
    expect(probe.startingStyleFor('waifu|x|'), ToolChoiceStyle.auto);
  });

  test('attachTools required sentinel is the string required', () {
    final payload = attachTools(
      <String, dynamic>{'model': 'x'},
      tools: tools,
      toolChoice: kToolChoiceRequired,
      style: ToolChoiceStyle.required,
    );
    expect(payload['tool_choice'], kToolChoiceRequired);
    expect(payload['tool_choice'], isNot(isA<Map>()));
  });
}
