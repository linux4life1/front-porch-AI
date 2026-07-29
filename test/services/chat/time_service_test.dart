// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TimeService (story-clock rewrite) behavioral tests — the extracted leaf,
// exercised without any LLM (the per-turn eval path is fed canned JSON via
// oneShotMode / the injected fireLLMEval). Pure StoryClock math is covered
// separately in story_clock_test.dart.
// Design: docs/design/story-calendar.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

TimeService makeService({
  void Function(String, dynamic)? onPending,
  void Function(String, int, String)? onPatch,
}) => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: onPending ?? (_, _) {},
  onPatchLastMessageRealismState: onPatch ?? (_, _, _) {},
);

/// Seed to a fixed, deterministic moment: Day 3 (Thu 2026-07-02).
void seedFixed(TimeService t, {String timeOfDay = 'evening'}) =>
    t.seedFromV2OrExt(
      dayCount: 3,
      timeOfDay: timeOfDay,
      passageOfTimeEnabled: true,
      storyStartDate: '2026-06-30', // a Tuesday
    );

Future<void> runEval(
  TimeService t, {
  String? oneShotText,
  Future<String?> Function(String)? fire,
  String recent = 'User: hi\nNia: hello',
}) => t.evaluateTimeProgressAndPostureIfNeeded(
  charName: 'Nia',
  recent: recent,
  shortTermTierName: 'Warm',
  onChunk: null,
  fireLLMEval: (p, {onChunk}) async => fire == null ? null : await fire(p),
  stripThinkBlocks: (s) => s,
  extractJsonBool: (text, key) {
    final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(text);
    return m == null ? null : m.group(1) == 'true';
  },
  setSpatialStance: (_) {},
  getCurrentSpatialStance: () => '',
  getCharacterEmotion: () => '',
  getEmotionIntensity: () => '',
  oneShotMode: oneShotText != null,
  oneShotText: oneShotText,
);

void main() {
  group('TimeService seeding + derivation', () {
    test('fixed-date seed derives period/day/weekday from the clock', () {
      final t = makeService();
      seedFixed(t);
      expect(t.timeOfDay, 'evening');
      expect(t.dayCount, 3);
      expect(t.narrativeWeekday, 'Thursday');
      expect(t.clock, DateTime.utc(2026, 7, 2, 18, 30));
      expect(t.storyStartDateIso, '2026-06-30');
      expect(t.startDayOfWeekAnchor, 2); // Tuesday
    });

    test('exact opening time (storyStartTime) beats the period default', () {
      final t = makeService();
      t.seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'night',
        passageOfTimeEnabled: true,
        storyStartDate: '1887-06-01',
        storyStartTime: '23:47',
      );
      expect(t.clock, DateTime.utc(1887, 6, 1, 23, 47));
      expect(t.timeOfDay, 'night');
      // Period-era year always renders in the long date.
      expect(t.displayDate, contains('1887'));
    });

    test('legacy-only seed anchors on today (Day N = today)', () {
      final t = makeService();
      t.seedFromV2OrExt(
        dayCount: 5,
        timeOfDay: 'morning',
        passageOfTimeEnabled: true,
      );
      expect(t.dayCount, 5);
      expect(StoryClock.dateOnly(t.clock), StoryClock.todayAnchor());
    });

    test('loadTimeScalars prefers canonical columns over legacy', () {
      final t = makeService();
      t.loadTimeScalars(
        timeOfDay: 'morning', // stale derived value — must lose
        dayCount: 1,
        startDayOfWeek: 1,
        passageOfTimeEnabled: true,
        storyClock: '2026-07-02T21:40:00.000Z',
        storyStartDate: '2026-06-30',
      );
      expect(t.clock, DateTime.utc(2026, 7, 2, 21, 40));
      expect(t.timeOfDay, 'night');
      expect(t.dayCount, 3);
    });

    test('legacy row synthesis preserves the displayed weekday', () {
      final t = makeService();
      // startDayOfWeek=1 (Mon), Day 5 → the old modulo-7 math showed Friday.
      t.loadTimeScalars(
        timeOfDay: 'morning',
        dayCount: 5,
        startDayOfWeek: 1,
        passageOfTimeEnabled: true,
      );
      expect(t.narrativeWeekday, 'Friday');
      expect(t.dayCount, 5);
      expect(t.timeOfDay, 'morning');
    });
  });

  group('TimeService manual control', () {
    test('nudge forward/back snaps periods and rolls days', () {
      String? patchedIso;
      final t = makeService(onPatch: (_, _, iso) => patchedIso = iso);
      seedFixed(t, timeOfDay: 'night'); // Thu 22:30
      t.nudgeTimePeriod(1);
      expect(t.timeOfDay, 'dawn');
      expect(t.dayCount, 4); // rolled into Friday
      expect(patchedIso, t.storyClockIso);
      t.nudgeTimePeriod(-1);
      expect(t.timeOfDay, 'night');
      expect(t.dayCount, 3);
    });

    test('setStartDate slides the whole timeline (Day N preserved)', () {
      final t = makeService();
      seedFixed(t); // Day 3, Thu 2026-07-02 18:30
      t.setStartDate(DateTime.utc(1887, 6, 1));
      expect(t.dayCount, 3);
      expect(t.clock, DateTime.utc(1887, 6, 3, 18, 30));
      expect(t.storyStartDateIso, '1887-06-01');
    });

    test('setClockDirect before Day 1 pulls the anchor back', () {
      final t = makeService();
      seedFixed(t);
      t.setClockDirect(DateTime.utc(2026, 6, 20, 9, 0));
      expect(t.dayCount, 1);
      expect(t.storyStartDateIso, '2026-06-20');
    });

    test('advanceTimePeriods respects the passage toggle', () {
      final t = makeService();
      seedFixed(t, timeOfDay: 'morning');
      t.advanceTimePeriods(2); // morning → late_morning → afternoon
      expect(t.timeOfDay, 'afternoon');
      t.setPassageOfTimeEnabled(false);
      t.advanceTimePeriods(3);
      expect(t.timeOfDay, 'afternoon'); // unchanged
    });
  });

  group('TimeService OOC time-skip detector', () {
    test('in-narrative "we drive for several hours" advances 3 hours', () {
      final pending = <String, dynamic>{};
      final t = makeService(onPending: (k, v) => pending[k] = v);
      seedFixed(t, timeOfDay: 'morning'); // 09:00
      t.detectOocTimeSkip('we drive for several hours');
      expect(t.clock, DateTime.utc(2026, 7, 2, 12, 0));
      expect(pending['time_skip_to'], contains('12:00 PM'));
    });

    test('"a few hours later" is +2h; OOC with skip language is +1h', () {
      final t = makeService();
      seedFixed(t, timeOfDay: 'morning');
      t.detectOocTimeSkip('a few hours later, they arrive');
      expect(t.clock, DateTime.utc(2026, 7, 2, 11, 0));
      t.detectOocTimeSkip('(ooc: skip ahead a bit)');
      expect(t.clock, DateTime.utc(2026, 7, 2, 12, 0));
    });

    test('OOC marker with no time language moves nothing', () {
      // A bare "(OOC: ...)" direction/flavor note used to cost a silent +1h.
      final t = makeService();
      seedFixed(t, timeOfDay: 'morning');
      final before = t.clock;
      t.detectOocTimeSkip('(ooc: she is very sweaty as a general rule)');
      expect(t.clock, before);
    });

    test(
      'an OOC skip owns the turn — the eval cannot double-advance',
      () async {
        // Field report: chip said "Time skip: 11:50 PM" while the sidebar
        // showed 1:05 AM next day — the skip stamped the chip, then the same
        // turn's scene-time eval re-counted the exchange and pushed the clock
        // past midnight. The skip is now the turn's only clock authority.
        final t = makeService();
        seedFixed(t, timeOfDay: 'night'); // Thu 22:30
        t.detectOocTimeSkip('(ooc: skip ahead an hour)');
        expect(t.clock, DateTime.utc(2026, 7, 2, 23, 30));
        await runEval(
          t,
          oneShotText: '{"minutes_elapsed": 75, "new_day": false}',
        );
        expect(t.clock, DateTime.utc(2026, 7, 2, 23, 30)); // unchanged
        // The next turn's eval advances normally again.
        await runEval(
          t,
          oneShotText: '{"minutes_elapsed": 10, "new_day": false}',
        );
        expect(t.clock, DateTime.utc(2026, 7, 2, 23, 40));
      },
    );

    test('"the next morning" jumps to 08:00 the following day', () {
      final t = makeService();
      seedFixed(t, timeOfDay: 'night'); // Thu 22:30
      t.detectOocTimeSkip('the next morning, sunlight woke them');
      expect(t.clock, DateTime.utc(2026, 7, 3, 8, 0));
      expect(t.dayCount, 4);
    });

    test('small-hours "next morning" stays the same calendar day', () {
      final t = makeService();
      seedFixed(t);
      t.setClockDirect(DateTime.utc(2026, 7, 2, 1, 30));
      t.detectOocTimeSkip('they wake up the next morning');
      expect(t.clock, DateTime.utc(2026, 7, 2, 8, 0));
    });

    test(
      '"a week later" and "next month" — the jumps the old model lacked',
      () {
        final t = makeService();
        seedFixed(t); // Thu Jul 2, 18:30
        t.detectOocTimeSkip('(ooc: a week later)');
        expect(t.clock, DateTime.utc(2026, 7, 9, 18, 30));
        t.detectOocTimeSkip('ooc: next month they meet again');
        expect(t.clock, DateTime.utc(2026, 8, 1, 9, 0));
      },
    );

    test('does nothing when passage is disabled or no trigger present', () {
      final t = makeService();
      seedFixed(t);
      final before = t.clock;
      t.detectOocTimeSkip('just a normal message about fun');
      expect(t.clock, before);
      t.setPassageOfTimeEnabled(false);
      t.detectOocTimeSkip('(ooc: timeskip several hours)');
      expect(t.clock, before);
    });
  });

  group('TimeService restore paths', () {
    test('restore prefers canonical storyClock; legacy keys synthesize', () {
      final t = makeService();
      seedFixed(t);
      t.restoreTimeFromRealismState({
        'timeOfDay': 'morning',
        'dayCount': 9,
        'storyClock': '2026-07-04T06:10:00.000Z',
        'storyStartDate': '2026-06-30',
      });
      expect(t.clock, DateTime.utc(2026, 7, 4, 6, 10));
      expect(t.dayCount, 5);

      // Legacy-only snapshot (old message): synthesized, day preserved.
      t.restoreTimeFromRealismState({'timeOfDay': 'evening', 'dayCount': 2});
      expect(t.timeOfDay, 'evening');
      expect(t.dayCount, 2);
    });

    test('swipe restore respects the nudge flag and passage gate', () {
      final t = makeService();
      seedFixed(t);
      final before = t.clock;
      t.restoreTimeForSwipeOrRegen({
        'storyClock': '2026-07-01T09:00:00.000Z',
        'storyStartDate': '2026-06-30',
      }, wasNudged: true);
      expect(t.clock, before); // nudged time survives the swipe
      t.restoreTimeForSwipeOrRegen({
        'storyClock': '2026-07-01T09:00:00.000Z',
        'storyStartDate': '2026-06-30',
      });
      expect(t.clock, DateTime.utc(2026, 7, 1, 9, 0));
    });
  });

  group('TimeService per-turn advancement', () {
    test(
      'one-shot text applies minutes_elapsed (clamped) with no LLM call',
      () async {
        final t = makeService();
        seedFixed(t, timeOfDay: 'morning'); // 09:00
        await runEval(
          t,
          oneShotText: '{"minutes_elapsed": 25, "new_day": false}',
        );
        expect(t.clock, DateTime.utc(2026, 7, 2, 9, 25));

        // A teleport attempt is clamped to the per-turn maximum.
        await runEval(
          t,
          oneShotText: '{"minutes_elapsed": 4000, "new_day": false}',
        );
        expect(
          t.clock,
          DateTime.utc(
            2026,
            7,
            2,
            9,
            25,
          ).add(const Duration(minutes: StoryClock.maxMinutesPerTurn)),
        );
      },
    );

    test('new_day from evening onward jumps to 08:00 next day', () async {
      final t = makeService();
      seedFixed(t); // evening 18:30
      await runEval(
        t,
        oneShotText: '{"minutes_elapsed": 0, "new_day": true}',
        recent: 'Nia: goodnight... *she falls asleep*\nUser: *morning comes*',
      );
      expect(t.clock, DateTime.utc(2026, 7, 3, 8, 0));

      // new_day mid-afternoon is ignored (not a valid transition).
      t.setClockDirect(DateTime.utc(2026, 7, 3, 14, 0));
      await runEval(
        t,
        oneShotText: '{"minutes_elapsed": 0, "new_day": true}',
        recent: 'Nia: *she wakes from her nap*',
      );
      expect(t.clock.hour, 14);
    });

    test(
      'hallucinated new_day without sleep/wake language is suppressed',
      () async {
        // The Misty bug: "the beach where we met yesterday" talk at 6:30 PM
        // produced new_day=true and slammed the story to next morning.
        final t = makeService();
        seedFixed(t); // evening 18:30
        await runEval(
          t,
          oneShotText: '{"minutes_elapsed": 10, "new_day": true}',
          recent:
              'User: *the car pulls into the lot at the beach where we met '
              'yesterday in the rainstorm*\nNia: It looks so calm today.',
        );
        // Only the clamped minutes applied — same evening, same day.
        expect(t.clock, DateTime.utc(2026, 7, 2, 18, 40));
        expect(t.dayCount, 3);
      },
    );

    test(
      'multi-call eval failure drifts deterministically, never freezes',
      () async {
        final t = makeService();
        seedFixed(t, timeOfDay: 'morning');
        await runEval(t, fire: (_) async => throw Exception('backend down'));
        expect(
          t.clock,
          DateTime.utc(2026, 7, 2, 9, StoryClock.failureDriftMinutes),
        );
      },
    );

    test('multi-call eval parses minutes + posture from flat JSON', () async {
      final t = makeService();
      seedFixed(t, timeOfDay: 'morning');
      await runEval(
        t,
        fire: (_) async =>
            '{"minutes_elapsed": 45, "new_day": false, "posture": "by the window"}',
      );
      expect(t.clock, DateTime.utc(2026, 7, 2, 9, 45));
    });

    test(
      'stall backstop snaps to the next period after enough 0-minute turns',
      () async {
        final t = makeService();
        seedFixed(t, timeOfDay: 'morning'); // 09:00
        for (var i = 0; i < StoryClock.stallBackstopTurns; i++) {
          await runEval(
            t,
            oneShotText: '{"minutes_elapsed": 0, "new_day": false}',
          );
        }
        // The final stalled turn triggered the snap (morning → late_morning).
        expect(t.clock, DateTime.utc(2026, 7, 2, 11, 30));
      },
    );

    test('passage disabled: one-shot is a no-op for the clock', () async {
      final t = makeService();
      seedFixed(t, timeOfDay: 'morning');
      t.setPassageOfTimeEnabled(false);
      final before = t.clock;
      await runEval(
        t,
        oneShotText: '{"minutes_elapsed": 120, "new_day": true}',
      );
      expect(t.clock, before);
    });
  });
}
