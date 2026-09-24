// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';

void main() {
  test('continue does not wear, a frozen clock is one beat, a night wears nothing', () {
    expect(
      awakeMinutesForBeat(
        continues: true,
        clockRunning: true,
        committedAwakeMinutes: 90,
      ),
      0,
    );
    expect(
      awakeMinutesForBeat(
        continues: false,
        clockRunning: false,
        committedAwakeMinutes: 90,
      ),
      kBodyBeatMinutes,
    );
    expect(
      awakeMinutesForBeat(
        continues: false,
        clockRunning: true,
        committedAwakeMinutes: 0,
      ),
      0,
    );
    expect(
      awakeMinutesForBeat(
        continues: false,
        clockRunning: true,
        committedAwakeMinutes: 90,
      ),
      90,
    );
  });

  test('a need that is off is neither worn nor shown', () {
    const keys = ['hunger', 'bladder', 'energy'];
    expect(needsThatAreOn(keys, const ['bladder']), ['hunger', 'energy']);
    expect(
      visibleNeeds(const {'hunger': 40, 'bladder': 10}, const ['bladder']),
      {'hunger': 40},
    );
    expect(
      awakeWearDeltas(
        120,
        BodyPace.normal,
        needsThatAreOn(keys, const ['bladder']),
      ),
      isNot(containsPair('bladder', anything)),
    );
  });

  test('a bath plus is the same at every pace', () {
    expect(paceScaledDrop(40, BodyPace.sloth), 40);
    expect(paceScaledDrop(40, BodyPace.normal), 40);
    expect(paceScaledDrop(40, BodyPace.fast), 40);
  });

  test('a run drop of 30 scales to 20, 30, and 40', () {
    expect(paceScaledDrop(-30, BodyPace.sloth), -20);
    expect(paceScaledDrop(-30, BodyPace.normal), -30);
    expect(paceScaledDrop(-30, BodyPace.fast), -40);
  });

  test('a few minutes do not wear the body', () {
    expect(awakeWearPoints(5), 0);
    expect(awakeWearDeltas(5, BodyPace.fast, ['hygiene']), isEmpty);
  });

  test('half an hour is one ordinary beat and two hours are four', () {
    expect(awakeWearPoints(30), kBodyWearPerBeat);
    expect(awakeWearPoints(120), 8);
    final sloth = awakeWearDeltas(120, BodyPace.sloth, ['hygiene']);
    final fast = awakeWearDeltas(120, BodyPace.fast, ['hygiene']);
    expect(sloth['hygiene']!.abs(), lessThan(8));
    expect(fast['hygiene']!.abs(), greaterThan(8));
  });

  test('one scene cannot empty a bar', () {
    expect(clampSceneDrop(current: 5, delta: -30), -4);
    expect(clampSceneDrop(current: 80, delta: -10), -10);
    expect(clampSceneDrop(current: 40, delta: 25), 25);
  });

  test('the time chip names the minutes and hides a skip', () {
    expect(
      timePassedLabel(minutes: 12, nextMorning: false, isSkip: false),
      '12 min',
    );
    expect(
      timePassedLabel(minutes: 60, nextMorning: false, isSkip: false),
      '1 hr',
    );
    expect(
      timePassedLabel(minutes: 150, nextMorning: false, isSkip: false),
      '2 hr 30 min',
    );
    expect(
      timePassedLabel(minutes: 30, nextMorning: true, isSkip: false),
      'Next morning',
    );
    expect(
      timePassedLabel(minutes: 180, nextMorning: false, isSkip: true),
      isNull,
    );
    expect(
      timePassedLabel(minutes: 0, nextMorning: false, isSkip: false),
      isNull,
    );
  });
}
