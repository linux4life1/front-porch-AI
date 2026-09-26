// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';

void main() {
  test('a need that is off is neither worn nor shown', () {
    const keys = ['hunger', 'bladder', 'energy'];
    expect(needsThatAreOn(keys, const ['bladder']), ['hunger', 'energy']);
    expect(
      visibleNeeds(const {'hunger': 40, 'bladder': 10}, const ['bladder']),
      {'hunger': 40},
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
      'same moment',
    );
  });
}
