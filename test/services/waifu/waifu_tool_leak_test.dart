// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: MiniMax-style ◁tool_call_begin▷ leaked into the spoken
// bubble as orange wire format. Native tool_calls was empty.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  const leak = '''
Give me just a moment to patch and build, darling.
◁tool_calls_section_begin▷◁tool_call_begin▷functions/edit:0◁tool_call_argument_begin▷{"path": "Sources/EPUBReader/Engine/EPUB/HTMLProcessor.swift", "old_string": "case .light: textColor = .label", "new_string": "case .light: textColor = .labelColor"}◁tool_call_end▷◁tool_calls_section_end▷
''';

  test('tool protocol is not visible speech', () {
    final visible = waifuVisibleText(leak);
    expect(visible, contains('darling'));
    expect(visible, isNot(contains('tool_call')));
    expect(visible, isNot(contains('old_string')));
    expect(visible, isNot(contains('HTMLProcessor')));
  });

  test('leaked MiniMax edit becomes a real tool call', () {
    final calls = waifuLeakedToolCalls(leak);
    expect(calls, hasLength(1));
    expect(calls.single.name, 'edit');
    expect(calls.single.arguments['path'], contains('HTMLProcessor.swift'));
    expect(calls.single.arguments['new_string'], contains('labelColor'));
  });

  test('native tool_calls win; leak is not double-run', () {
    const native = LlmToolCall(name: 'read', arguments: {'path': 'a.swift'});
    final resp = LlmToolResponse(calls: const [native], text: leak);
    expect(waifuEffectiveToolCalls(resp).single.name, 'read');
  });

  test('empty native calls salvage the leak so the turn does not wrap up', () {
    const resp = LlmToolResponse(calls: [], text: leak);
    expect(waifuEffectiveToolCalls(resp), isNotEmpty);
  });
}
