// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// [today: …] parser: strip from visible reply; empty tag clears.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;

void main() {
  test('no tag keeps the reply and reports null line', () {
    const raw = 'She stacks the books and looks at the door.';
    final parsed = TodayLineTag.parse(raw);
    expect(parsed.visible, raw);
    expect(parsed.line, isNull);
  });

  test('tag is stripped and the sentence is held', () {
    const raw =
        'She stacks the books.\n[today: Finish the lighthouse log before the tide.]';
    final parsed = TodayLineTag.parse(raw);
    expect(parsed.visible, 'She stacks the books.');
    expect(parsed.line, 'Finish the lighthouse log before the tide.');
  });

  test('empty tag means abandon', () {
    final parsed = TodayLineTag.parse('Never mind.\n[today:  ]');
    expect(parsed.visible, 'Never mind.');
    expect(parsed.line, isEmpty);
  });

  test('last tag wins and whitespace collapses', () {
    final parsed = TodayLineTag.parse(
      'Hi [today: first   draft]\n[today:  Get Saturday done.  ]',
    );
    expect(parsed.visible.contains('[today'), isFalse);
    expect(parsed.line, 'Get Saturday done.');
  });

  test('parseEvalSentence omit returns null', () {
    expect(TodayLineTag.parseEvalSentence('{"minutes_elapsed": 5}'), isNull);
    expect(TodayLineTag.parseEvalSentence(''), isNull);
  });

  test('parseEvalSentence none and empty abandon', () {
    expect(
      TodayLineTag.parseEvalSentence('{"today_sentence": "none"}'),
      isEmpty,
    );
    expect(TodayLineTag.parseEvalSentence('{"today_sentence": ""}'), isEmpty);
    expect(TodayLineTag.parseEvalSentence('none'), isEmpty);
  });

  test('parseEvalSentence keeps the trimmed sentence', () {
    expect(
      TodayLineTag.parseEvalSentence(
        '{"today_sentence": "  Finish the lighthouse log.  "}',
      ),
      'Finish the lighthouse log.',
    );
  });

  test('tool flatten and JSON parse share the same clamp', () {
    final json = realismToolCallToJson(kSceneTimeTool, [
      const LlmToolCall(
        name: kSceneTimeTool,
        arguments: {
          'minutes_elapsed': 4,
          'today_sentence': '  Finish the lighthouse log.  ',
        },
      ),
    ]);
    expect(TodayLineTag.parseEvalSentence(json!), 'Finish the lighthouse log.');

    final empty = realismToolCallToJson(kSceneTimeTool, [
      const LlmToolCall(
        name: kSceneTimeTool,
        arguments: {'minutes_elapsed': 4, 'today_sentence': ''},
      ),
    ]);
    expect(empty, contains('"today_sentence":""'));
    expect(TodayLineTag.parseEvalSentence(empty!), isEmpty);

    final none = realismToolCallToJson(kSceneTimeTool, [
      const LlmToolCall(
        name: kSceneTimeTool,
        arguments: {'minutes_elapsed': 4, 'today_sentence': 'none'},
      ),
    ]);
    expect(TodayLineTag.parseEvalSentence(none!), isEmpty);
  });
}
