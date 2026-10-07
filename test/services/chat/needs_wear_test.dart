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

// Needs v2: the story clock wears hunger, bladder and energy at fixed rates
// per story hour (docs/design/needs-on-the-clock.md). These pin the rates,
// the pace scaling, the carried fractions, the one-warning-turn stop on
// screen and the skip floors off screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/needs_wear.dart';

const _three = ['hunger', 'bladder', 'energy'];

void main() {
  group('rates', () {
    test('one story hour at Normal is 6, 15 and 5 points', () {
      final w = needsWearForSpan(
        minutes: 60,
        pace: BodyPace.normal,
        on: _three,
      );
      expect(w.points, {'hunger': 6, 'bladder': 15, 'energy': 5});
      expect(w.carry.values.every((c) => c == 0), isTrue);
    });

    test('the other four needs never wear with time', () {
      final w = needsWearForSpan(
        minutes: 600,
        pace: BodyPace.normal,
        on: const ['social', 'fun', 'hygiene', 'comfort'],
      );
      expect(w.points, isEmpty);
    });

    test('a need that is off keeps its carry and takes no wear', () {
      final w = needsWearForSpan(
        minutes: 60,
        pace: BodyPace.normal,
        on: const ['hunger'],
        carry: const {'bladder': 0.5},
      );
      expect(w.points, {'hunger': 6});
      expect(w.carry['bladder'], 0.5);
    });

    test('pace scales the wear like a scene drop: two thirds, one, four '
        'thirds', () {
      final sloth = needsWearForSpan(
        minutes: 60,
        pace: BodyPace.sloth,
        on: const ['hunger'],
      );
      final fast = needsWearForSpan(
        minutes: 60,
        pace: BodyPace.fast,
        on: const ['hunger'],
      );
      expect(sloth.points['hunger'], 4);
      expect(fast.points['hunger'], 8);
    });
  });

  group('fractions carry over', () {
    test('ten 2-minute beats cost what one 20-minute beat costs', () {
      var carry = const <String, double>{};
      var total = 0;
      for (var i = 0; i < 10; i++) {
        final w = needsWearForSpan(
          minutes: 2,
          pace: BodyPace.normal,
          on: const ['hunger'],
          carry: carry,
        );
        total += w.points['hunger']!;
        carry = w.carry;
      }
      final whole = needsWearForSpan(
        minutes: 20,
        pace: BodyPace.normal,
        on: const ['hunger'],
      );
      expect(total, whole.points['hunger']);
      expect(total, 2);
    });

    test('a same-moment beat charges nothing and keeps the carry', () {
      final w = needsWearForSpan(
        minutes: 0,
        pace: BodyPace.normal,
        on: _three,
        carry: const {'hunger': 0.7},
      );
      expect(w.isEmpty, isTrue);
      expect(w.carry['hunger'], 0.7);
    });
  });

  group('on screen', () {
    test('a beat stops at 1 when the bar began above the crisis band', () {
      expect(
        wornBar(need: 'bladder', current: 30, drop: 45, offScreen: false),
        1,
      );
    });

    test('a bar already in the crisis band can be worn to 0', () {
      expect(
        wornBar(need: 'bladder', current: 8, drop: 10, offScreen: false),
        0,
      );
    });

    test('an ordinary drop simply subtracts', () {
      expect(
        wornBar(need: 'hunger', current: 75, drop: 3, offScreen: false),
        72,
      );
    });
  });

  group('off screen (a skip, a night, time away)', () {
    test('a 6-hour skip from 80 / 80 / 80 lands on 45 / 60 / 50', () {
      final w = needsWearForSpan(
        minutes: 360,
        pace: BodyPace.normal,
        on: _three,
      );
      final landed = {
        for (final need in _three)
          need: wornBar(
            need: need,
            current: 80,
            drop: w.points[need]!,
            offScreen: true,
          ),
      };
      expect(landed, {'hunger': 45, 'bladder': 60, 'energy': 50});
    });

    test('a bar already under its floor is left where it is', () {
      expect(
        wornBar(need: 'bladder', current: 50, drop: 90, offScreen: true),
        50,
      );
    });

    test('a night with no sleep in the reply leaves energy at 25', () {
      final w = needsWearForSpan(
        minutes: 8 * 60,
        pace: BodyPace.normal,
        on: const ['energy'],
      );
      expect(
        wornBar(
          need: 'energy',
          current: 60,
          drop: w.points['energy']!,
          offScreen: true,
        ),
        25,
      );
    });
  });

  test('carry maps read back from JSON-shaped data', () {
    expect(wearCarryFrom({'hunger': 0.25, 'bladder': 1, 'x': 'no'}), {
      'hunger': 0.25,
      'bladder': 1.0,
    });
  });
}
