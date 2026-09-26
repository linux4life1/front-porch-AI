// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// THE STORY DATE MUST NOT WANDER, AND SPEECH MUST NOT MOVE IT.
//
// These are the two ways the clock was handing the model facts that contradict
// the notes it is reading in the same prompt — the "day 28 / time 16 of 461"
// cluster. Neither is a wording problem, so neither has a wording fix.
//
// 1. THE STORY DATE FOLLOWED THE REAL CALENDAR. Sessions written before the
//    Story Calendar (v38) have NULL story_clock/story_start_date. TimeService
//    synthesised them from period + day number against TODAY — and nothing ever
//    wrote the answer back, so it re-synthesised on every open against a
//    different today. Open on Monday, it says Monday; reopen on Saturday, it
//    says Saturday, while the journal cards and the recap still say Monday.
//    96 of 109 sessions in the maintainer's own library were in that state.
//
// 2. A CHARACTER SAYING "NEXT WEEK" TRAVELLED THERE. detectOocTimeSkip matched
//    its phrase list anywhere in the message, quoted dialogue included. Real
//    damage, from real chats: "will you give your donors a new video next
//    week?" moved the story from Day 1 to Day 8, and "why wait till next week
//    for the Gym video" did it again a few turns later and made it stick;
//    "even though we just woke up a few hours ago" cost another chat a whole
//    day. The skip then claims the turn, so the eval's correct verdict of a few
//    minutes is thrown away in favour of the phantom week.
//
// Everything here is deterministic: fixed UTC dates, no wall clock, no LLM.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// One-path reader: backfill then [TimeService.applySlotClock] from
/// `story_clock_after` — the same door `_applyTipClock` uses on swipe.
void applyOnePathClock(TimeService t, Map<String, dynamic> realism) {
  final user = ChatMessage(text: 'Hi.', sender: 'You', isUser: true);
  final bot = ChatMessage(
    text: 'Ok.',
    sender: 'Nia',
    isUser: false,
    metadata: {'realism_state': realism},
  );
  backfillSlotClocks([user, bot], liveClock: t.clock, startDate: t.startDate);
  t.applySlotClock(resolved: slotClockAfter(bot.metadata));
}

TimeService makeService({void Function(String, dynamic)? onPending}) =>
    TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: onPending ?? (_, _) {},
      onPatchLastMessageRealismState: (_, _, _) {},
    );

/// Day 3 of a story that began Tuesday 2026-06-30 — the same fixed anchor the
/// neighbouring suites use, so numbers compare by eye.
void seedFixed(TimeService t) => t.seedFromV2OrExt(
  dayCount: 3,
  timeOfDay: 'evening',
  storyStartDate: '2026-06-30',
);

void main() {
  group('a synthesised story date is reported so it can be frozen', () {
    test('a pre-calendar row announces that it was invented', () {
      final t = makeService();
      t.loadTimeScalars(
        timeOfDay: 'morning',
        dayCount: 5,
        startDayOfWeek: 1,
        // Both canonical columns NULL — the 96-of-109 case.
      );

      expect(
        t.canonicalClockWasSynthesised,
        isTrue,
        reason:
            'the loader is the only place that knows the date was made up. '
            'If it does not say so, the caller cannot write it back, and the '
            'chat gets a different date the next time it is opened',
      );
      // And what it invented still says what these chats say today — the fix
      // freezes the date, it does not move anyone to a new one.
      expect(t.dayCount, 5);
      expect(t.timeOfDay, 'morning');
      expect(t.narrativeWeekday, 'Friday');
    });

    test('a row that already carries both columns claims nothing', () {
      final t = makeService();
      t.loadTimeScalars(
        timeOfDay: 'morning',
        dayCount: 1,
        startDayOfWeek: 1,
        storyClock: '2026-07-02T21:40:00.000Z',
        storyStartDate: '2026-06-30',
      );

      expect(
        t.canonicalClockWasSynthesised,
        isFalse,
        reason:
            're-writing a row that is already correct on every single chat '
            'open is a pointless write on the hot open path',
      );
      expect(t.clock, DateTime.utc(2026, 7, 2, 21, 40));
    });
  });

  group(
    'a half-populated row is completed from the story, not the calendar',
    () {
      test('an anchor without a clock counts Day N forward from Day 1', () {
        final t = makeService();
        t.loadTimeScalars(
          timeOfDay: 'evening',
          dayCount: 3,
          startDayOfWeek: 0,
          storyStartDate: '1887-06-01',
        );

        // Day 3 of an 1887 story is 1887-06-03. The old path put the "current"
        // moment on today's real date while keeping 1887 as Day 1, which made
        // this a chat on roughly Day 50,000.
        expect(t.clock, DateTime.utc(1887, 6, 3, 18, 30));
        expect(t.dayCount, 3);
        expect(t.startDate, DateTime.utc(1887, 6, 1));
      });

      test('a clock without an anchor puts Day 1 behind it, not on today', () {
        final t = makeService();
        t.loadTimeScalars(
          timeOfDay: 'evening',
          dayCount: 4,
          startDayOfWeek: 0,
          storyClock: '2026-07-02T18:30:00.000Z',
        );

        expect(t.clock, DateTime.utc(2026, 7, 2, 18, 30));
        expect(
          t.startDate,
          DateTime.utc(2026, 6, 29),
          reason:
              'Day 4 means Day 1 was three days ago; deriving it from the '
              'wall calendar instead made Day N a function of when you opened '
              'the chat rather than of the story',
        );
        expect(t.dayCount, 4);
      });
    },
  );

  group('a swipe on an old message must not drag the timeline to today', () {
    test('a pre-calendar snapshot is read against this story\'s Day 1', () {
      final t = makeService();
      seedFixed(t); // Day 1 = 2026-06-30.

      // An old message carries only "Day 2, evening" — no storyClock at all.
      applyOnePathClock(t, {'timeOfDay': 'evening', 'dayCount': 2});

      expect(
        t.clock,
        DateTime.utc(2026, 7, 1, 18, 30),
        reason:
            'Day 2 of THIS story is the day after its Day 1. Synthesising '
            'it against the real calendar moved the whole conversation onto '
            'whatever date the user happened to be swiping on — mid-chat, and '
            'contradicting every message above it',
      );
      expect(t.dayCount, 2);
      expect(t.timeOfDay, 'evening');
    });

    test('the snapshot may still re-anchor Day 1 when it carries one', () {
      final t = makeService();
      seedFixed(t);
      t.loadTimeScalars(
        timeOfDay: 'evening',
        dayCount: 2,
        startDayOfWeek: 1,
        storyStartDate: '1887-06-01',
      );
      applyOnePathClock(t, {
        'timeOfDay': 'morning',
        'dayCount': 2,
        'storyStartDate': '1887-06-01',
      });
      expect(t.clock, DateTime.utc(1887, 6, 2, 9, 0));
      expect(t.dayCount, 2);
    });
  });

  group('quoted speech is not a time machine', () {
    /// The verbatim lines that moved real chats. Kept as-is (they are the
    /// evidence) with the surrounding narration that made them look innocuous.
    test('"a new video next week?" does not jump the story seven days', () {
      final t = makeService();
      seedFixed(t); // Thu 2026-07-02, 18:30, Day 3.
      final before = t.clock;

      t.detectOocTimeSkip(
        '*I trail off slowly* "Mistress? will you give your donors a new '
        'video next week?" *I lead on as I look up at you*',
      );

      expect(
        t.clock,
        before,
        reason:
            'asking about next week is not going to next week. This exact '
            'line moved a real chat from Day 1 to Day 8',
      );
      expect(t.dayCount, 3);
    });

    test('"why wait till next week" does not either', () {
      final t = makeService();
      seedFixed(t);
      final before = t.clock;
      t.detectOocTimeSkip(
        '*I tease playfully* "why wait till next week for the Gym video, do '
        'it tomorrow"',
      );
      expect(t.clock, before);
    });

    test('"we just woke up a few hours ago" does not cost a day', () {
      final t = makeService();
      seedFixed(t);
      final before = t.clock;

      t.detectOocTimeSkip(
        '*I mumble softly* "I feel tired now, even though we just woke up a '
        'few hours ago.. I just want to cuddle"',
      );

      expect(
        t.clock,
        before,
        reason:
            'the sentence says the waking already happened, hours ago and '
            'behind us. Matching `woke up` fired nextMorning and threw the '
            'story to 8am the following day',
      );
    });

    test('a narrated skip in the same message still fires', () {
      final t = makeService();
      seedFixed(t);

      // The real message this is taken from carried both: spoken flavour AND a
      // genuine instruction. Stripping speech must not cost the instruction.
      t.detectOocTimeSkip(
        '*I lick you clean* "Same time next week" *I moan*  '
        '(OOC: fast forward to next week)',
      );

      expect(t.clock, DateTime.utc(2026, 7, 9, 18, 30));
      expect(t.dayCount, 10);
    });

    test('narration outside quotes is untouched by the strip', () {
      // 1,043 of the 1,050 trigger phrases in the maintainer's library are
      // narration like these. None of them may change behaviour.
      final t = makeService();
      seedFixed(t);
      t.detectOocTimeSkip('*we drive for several hours*');
      expect(t.clock, DateTime.utc(2026, 7, 2, 21, 30));

      final t2 = makeService();
      seedFixed(t2);
      t2.detectOocTimeSkip('(OOC: timeskip to the next morning)');
      expect(t2.clock, DateTime.utc(2026, 7, 3, 8, 0));
    });

    test('curly quotes are speech too', () {
      final t = makeService();
      seedFixed(t);
      final before = t.clock;
      t.detectOocTimeSkip('“I will see you next week,” she smiled.');
      expect(
        t.clock,
        before,
        reason:
            'phones and word processors produce these by default, so a '
            'straight-quotes-only strip would leave the bug alive for anyone '
            'typing on one',
      );
    });

    test('an unterminated quote keeps the old, firing behaviour', () {
      final t = makeService();
      seedFixed(t);
      t.detectOocTimeSkip('*she said* "several hours pass and the rain stops');
      expect(
        t.clock,
        DateTime.utc(2026, 7, 2, 21, 30),
        reason:
            'a lone quote mark must not swallow the rest of the message — '
            'the conservative direction is to behave exactly as before',
      );
    });

    test('a spoken skip does not silently steal the turn from the eval', () {
      // The compounding half of the bug: a fired skip sets the "this turn is
      // mine" flag, so the eval's own verdict is discarded. A phantom skip
      // therefore replaced a correct few-minutes advance with a phantom week.
      final pending = <String, dynamic>{};
      final t = makeService(onPending: (k, v) => pending[k] = v);
      seedFixed(t);

      t.detectOocTimeSkip('"maybe next week," she said, not looking up');

      expect(
        pending['time_skip_to'],
        isNull,
        reason: 'no skip happened, so no skip chip and no claim on the turn',
      );
    });
  });

  group('the wall clock is read in exactly one place', () {
    test('two loads of the same legacy row agree with each other', () {
      // Not a tautology: the today-anchored synthesis is a pure function of
      // DateTime.now(), so two loads a day apart disagreed. This pins that the
      // only surviving wall-clock read is the both-columns-NULL branch, whose
      // whole point is that the caller freezes it immediately.
      final a = makeService();
      final b = makeService();
      const args = (
        timeOfDay: 'afternoon',
        dayCount: 6,
        startDayOfWeek: 3,
        storyClock: '2026-07-02T14:30:00.000Z',
        storyStartDate: '2026-06-27',
      );
      for (final t in [a, b]) {
        t.loadTimeScalars(
          timeOfDay: args.timeOfDay,
          dayCount: args.dayCount,
          startDayOfWeek: args.startDayOfWeek,
          storyClock: args.storyClock,
          storyStartDate: args.storyStartDate,
        );
      }
      expect(a.clock, b.clock);
      expect(a.startDate, b.startDate);
      expect(a.clock, DateTime.utc(2026, 7, 2, 14, 30));
      expect(StoryClock.dayCountFor(a.clock, a.startDate), 6);
    });
  });
}
