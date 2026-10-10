// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Older history above vs new rows below, when the last line is the same
// before and after. The first row decides: a new message object first is
// older history, the same object first is new rows. Identity, not text, so
// an older page that starts with the same words as the old first row still
// reads as older history.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/stage/transcript_auto_scroll.dart';

ChatMessage _m(String text, {bool user = false}) =>
    ChatMessage(text: text, sender: user ? 'You' : 'Iris', isUser: user);

bool _prepend(List<ChatMessage> before, List<ChatMessage> after) =>
    isTranscriptPrepend(
      prevLen: before.length,
      prevTip: transcriptTipKey(before),
      nextLen: after.length,
      nextTip: transcriptTipKey(after),
      prevHead: transcriptHeadKey(before),
      nextHead: transcriptHeadKey(after),
    );

void main() {
  final head = _m('ok');
  final tip = _m('See you tomorrow.');
  final before = [head, _m('Night.', user: true), tip];

  test('rows added below with a repeated last line are not older history', () {
    final after = [...before, _m('Night.', user: true), _m(tip.text)];
    expect(_prepend(before, after), isFalse);
    expect(
      classifyTranscriptGrowth(
        sessionId: 's',
        prevSession: 's',
        prevLen: before.length,
        prevTip: transcriptTipKey(before),
        nextLen: after.length,
        nextTip: transcriptTipKey(after),
        prevHead: transcriptHeadKey(before),
        nextHead: transcriptHeadKey(after),
      ),
      TranscriptGrowth.other,
    );
  });

  test('an older page is older history', () {
    final after = [_m('Morning.'), _m('Hi.', user: true), ...before];
    expect(_prepend(before, after), isTrue);
  });

  test('an older page that starts with the same words as the old first row '
      'is still older history', () {
    final after = [_m('ok'), _m('Hi.', user: true), ...before];
    expect(_prepend(before, after), isTrue);
  });
}
