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

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/afk_flavor.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

void main() {
  const storm = DailyWeather(
    condition: WeatherCondition.storm,
    temp: TempBand.cold,
    season: 'winter',
  );
  const fine = DailyWeather(
    condition: WeatherCondition.clear,
    temp: TempBand.warm,
    season: 'summer',
  );

  group('AfkFlavor.timePhrase / spanDirective', () {
    test('pace maps to banded phrases; single-period span adds nothing', () {
      expect(AfkFlavor.timePhrase(1), 'A few hours have passed.');
      expect(AfkFlavor.timePhrase(3), 'Much of the day has slipped by.');
      expect(AfkFlavor.timePhrase(6), 'A full day has passed.');
      expect(AfkFlavor.spanDirective(1), isEmpty);
      expect(AfkFlavor.spanDirective(3), contains('stretch of hours'));
      expect(AfkFlavor.spanDirective(6), contains('montage'));
    });
  });

  group('AfkFlavor.directives (priority ladder + rotation)', () {
    test('night leads with sleep; memory drift rides second', () {
      final lines = AfkFlavor.directives(timeOfDay: 'night');
      expect(lines.first, contains('sleep'));
      expect(lines, hasLength(2));
      expect(lines[1], contains('memory'));
    });

    test('rough weather leads when no night; fine day goes outdoors', () {
      expect(
        AfkFlavor.directives(timeOfDay: 'morning', weather: storm).first,
        contains('keeping them in'),
      );
      expect(
        AfkFlavor.directives(timeOfDay: 'morning', weather: fine).first,
        contains('outdoors'),
      );
    });

    test('fixation intrudes; memory drift is the universal floor', () {
      final withFix = AfkFlavor.directives(
        timeOfDay: 'afternoon',
        fixation: 'the storm',
      );
      expect(withFix.first, contains('the storm'));
      final bare = AfkFlavor.directives(timeOfDay: 'afternoon');
      expect(bare.single, contains('memory'));
    });

    test('rotation varies the second line deterministically', () {
      List<String> at(int i) => AfkFlavor.directives(
        timeOfDay: 'night',
        weather: storm,
        fixation: 'the letter',
        snapshotIndex: i,
      );
      // Same index → identical (deterministic).
      expect(at(0), at(0));
      // Consecutive snapshots pick different secondaries.
      final seconds = {at(0)[1], at(1)[1], at(2)[1]};
      expect(seconds.length, greaterThan(1));
      // Primary stays the strongest flavor throughout.
      for (var i = 0; i < 3; i++) {
        expect(at(i).first, contains('sleep'));
      }
    });

    test('never contains digits (words-only cue contract)', () {
      for (final lines in [
        AfkFlavor.directives(timeOfDay: 'night', weather: storm),
        AfkFlavor.directives(timeOfDay: 'morning', weather: fine),
        [AfkFlavor.timePhrase(6), AfkFlavor.spanDirective(6)],
      ]) {
        for (final l in lines) {
          expect(l, isNot(matches(RegExp(r'\d'))));
        }
      }
    });
  });
}
