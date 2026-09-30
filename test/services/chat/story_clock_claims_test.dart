// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Post-reply clock claims. Red-proven 2026-08-15: dropping the
// "six in the morning" spoken form leaves the Senjumaru excerpt null
// and the 8:05-vs-6am class unfixed.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  final eightOhFive = DateTime.utc(2026, 8, 14, 8, 5);

  group('clockNamedInReply', () {
    test('Senjumaru all-nighter names 6:00, not 8:05', () {
      const reply =
          'a Royal Guard who is standing on a human footpath at six '
          'in the morning with a half-built Senkaimon and a butterfly '
          'that just transmitted a Quincy\'s private morning thoughts';
      expect(
        clockNamedInReply(reply, eightOhFive),
        DateTime.utc(2026, 8, 14, 6, 0),
      );
    });

    test('think-block quoting the injection is ignored', () {
      const reply =
          '<think>The story notes say it\'s now 8:00 AM on Friday.</think>\n'
          '*The river moves slow and silver in the dawn.*';
      // Bare "in the dawn" in the visible prose, no numeric clock.
      expect(
        clockNamedInReply(reply, eightOhFive),
        DateTime.utc(2026, 8, 14, 6, 0),
      );
    });

    test('think-only 8:00 AM does not move the clock', () {
      const reply =
          '<think>The story notes say it\'s now 8:00 AM on Friday.</think>\n'
          '*She folds the six golden arms and says nothing about the hour.*';
      expect(clockNamedInReply(reply, eightOhFive), isNull);
    });

    test('6am / 6 a.m. parse, "another six hours" does not', () {
      expect(
        clockNamedInReply('It is 6am and the street is empty.', eightOhFive),
        DateTime.utc(2026, 8, 14, 6, 0),
      );
      expect(
        clockNamedInReply(
          'the ramen shop that won\'t open for another six hours',
          eightOhFive,
        ),
        isNull,
      );
    });

    test('future bounds do not count (until/by/before)', () {
      expect(
        clockNamedInReply('stay until 6am if you have to', eightOhFive),
        isNull,
      );
      expect(clockNamedInReply('be there by 6:00 AM', eightOhFive), isNull);
    });

    test('a 2pm scene saying midnight is too far to trust', () {
      expect(
        clockNamedInReply(
          'It is midnight and the house is quiet.',
          DateTime.utc(2026, 8, 14, 14, 0),
        ),
        isNull,
      );
    });

    test('already-agreeing 8:05 AM does not produce a move', () {
      expect(
        clockNamedInReply('It is 8:05 AM on the river path.', eightOhFive),
        isNull,
      );
    });

    test('last present claim wins when two hours are named', () {
      expect(
        clockNamedInReply(
          'I thought it was 5am. It is 6:15 AM now.',
          eightOhFive,
        ),
        DateTime.utc(2026, 8, 14, 6, 15),
      );
    });

    test('it is / it\'s / it\u2019s all name a present 7:15', () {
      final fivePm = DateTime.utc(2026, 8, 14, 17, 0);
      final sevenFifteen = DateTime.utc(2026, 8, 14, 19, 15);
      expect(clockNamedInReply("It's 7:15 pm", fivePm), sevenFifteen);
      expect(clockNamedInReply('It\u2019s 7:15 pm', fivePm), sevenFifteen);
      expect(
        clockNamedInReply("it's seven in the evening", fivePm),
        DateTime.utc(2026, 8, 14, 19, 0),
      );
      expect(clockNamedInReply('It is 7:15 p.m.', fivePm), sevenFifteen);
    });

    test('a possessive \'s hour is still a schedule, not the present', () {
      expect(
        clockNamedInReply(
          "Bob's 7:15 pm train",
          DateTime.utc(2026, 8, 14, 17, 0),
        ),
        isNull,
      );
    });
  });
}
