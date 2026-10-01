// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A model that never emits </think> sends the whole output as
// reasoning_content. That must stay in the Thought chip. A short parked
// spoken line (the Flora poke) still lifts into the bubble.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

final _draft = List.generate(
  14,
  (i) => 'Draft line $i: I should keep her dominant and mention the clock.',
).join('\n\n');
final _reply = List.generate(
  18,
  (i) => '*Reply paragraph $i.* "Spoken line $i."',
).join('\n\n');

String _streamReasoningOnly() {
  final ingest = ReasoningIngest(wrap: true);
  final out = StringBuffer();
  final all = '$_draft\n\n$_reply';
  for (var i = 0; i < all.length; i += 7) {
    out.write(
      ingest.onReasoning(all.substring(i, (i + 7).clamp(0, all.length))),
    );
  }
  out.write(ingest.finish());
  return out.toString();
}

void main() {
  test('closed think-only reasoning dump is NOT lifted into the bubble', () {
    final streamed = _streamReasoningOnly().trim();
    expect(streamed.startsWith('<think>'), isTrue);
    final saved = resolveMouthSpeech(streamed);
    final m = ChatMessage(text: saved, sender: 'Tess', isUser: false);
    expect(saved, startsWith('<think>'));
    expect(m.displayText, isEmpty);
    expect(m.displayText, isNot(contains('Draft line 0')));
    expect(m.thinkingContent, contains('Draft line 0'));
  });

  test('a short parked spoken line is still lifted (Flora case)', () {
    final saved = resolveMouthSpeech(
      '<think>She looks down the porch steps.</think>',
    );
    expect(saved, 'She looks down the porch steps.');
  });

  test('two short paragraphs still lift; a third stays tagged', () {
    expect(
      resolveMouthSpeech('<think>One line.\n\nSecond line.</think>'),
      'One line.\n\nSecond line.',
    );
    final three = '<think>One.\n\nTwo.\n\nThree.</think>';
    expect(resolveMouthSpeech(three), three);
  });

  test('a think-only body over 800 characters stays tagged', () {
    final long = 'word ' * 200;
    expect(long.trim().length, greaterThan(kLiftThinkMaxChars));
    final saved = resolveMouthSpeech('<think>$long</think>');
    expect(saved, startsWith('<think>'));
  });
}
