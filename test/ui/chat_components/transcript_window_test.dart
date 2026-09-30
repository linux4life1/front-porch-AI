// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/session_open_window.dart';
import 'package:front_porch_ai/ui/chat_components/stage/transcript_window.dart';

void main() {
  test('opening a long chat mounts the latest lines, not the start', () {
    final span = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 11270,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    expect(span.end, 11270);
    expect(span.start, 11270 - kSessionOpenWindow);
    expect(span.length, kSessionOpenWindow);
  });

  test('a short chat mounts every row', () {
    final span = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 11,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    expect(span.start, 0);
    expect(span.end, 11);
  });

  test('older rows arriving behind the reader do not move the window', () {
    final span = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 24,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    span.apply(
      previousLength: 24,
      nextLength: 224,
      opened: false,
      prepended: true,
      nearTop: false,
    );
    expect(span.start, 200);
    expect(span.end, 224);
    expect(span.length, 24);
  });

  test('reaching the top includes the older rows that just arrived', () {
    final span = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 24,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    span.apply(
      previousLength: 24,
      nextLength: 224,
      opened: false,
      prepended: true,
      nearTop: true,
    );
    expect(span.start, 0);
    expect(span.end, 224);
  });

  test('revealOlder walks upward and stops at the first row', () {
    final span = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 100,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    expect(span.revealOlder(100), isTrue);
    expect(span.start, 100 - kSessionOpenWindow - kTranscriptRevealPage);
    expect(span.revealOlder(100, page: 1000), isTrue);
    expect(span.start, 0);
    expect(span.revealOlder(100), isFalse);
  });

  test('a new reply extends the tip and leaves a history read alone', () {
    final atTip = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 30,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    atTip.apply(
      previousLength: 30,
      nextLength: 31,
      opened: false,
      prepended: false,
      nearTop: false,
    );
    expect(atTip.end, 31);

    final reading = TranscriptWindow()..end = 10;
    reading.start = 0;
    reading.apply(
      previousLength: 30,
      nextLength: 31,
      opened: false,
      prepended: false,
      nearTop: true,
    );
    expect(reading.end, 10);
  });

  test('revealAround brings a journal target into the mounted span', () {
    final span = TranscriptWindow()
      ..apply(
        previousLength: 0,
        nextLength: 500,
        opened: true,
        prepended: false,
        nearTop: false,
      );
    span.revealAround(40, 500);
    expect(span.start, lessThanOrEqualTo(40));
    expect(span.end, greaterThan(40));
    expect(span.length, lessThanOrEqualTo(kSessionOpenWindow));
  });
}
