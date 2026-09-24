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

import 'package:front_porch_ai/services/chat/weather_engine.dart';

void main() {
  group('WeatherEngine determinism', () {
    test('same inputs always yield the same weather (repeat calls)', () {
      final date = DateTime(2026, 7, 21);
      for (int day = 1; day <= 30; day++) {
        final a = WeatherEngine.weatherFor(
          sessionSeed: 'session-abc',
          dayCount: day,
          date: date,
        );
        final b = WeatherEngine.weatherFor(
          sessionSeed: 'session-abc',
          dayCount: day,
          date: date,
        );
        expect(a, equals(b), reason: 'day $day must be reproducible');
      }
    });

    test('different sessions diverge (seed matters)', () {
      final date = DateTime(2026, 7, 21);
      final seqA = <WeatherCondition>[];
      final seqB = <WeatherCondition>[];
      for (int day = 1; day <= 40; day++) {
        seqA.add(
          WeatherEngine.weatherFor(
            sessionSeed: 'session-a',
            dayCount: day,
            date: date.add(Duration(days: day)),
          ).condition,
        );
        seqB.add(
          WeatherEngine.weatherFor(
            sessionSeed: 'session-b',
            dayCount: day,
            date: date.add(Duration(days: day)),
          ).condition,
        );
      }
      expect(seqA, isNot(equals(seqB)));
    });

    test('golden sequence is pinned (cross-release stability)', () {
      // If this test ever fails, the engine's output changed for EXISTING
      // chats — that is a behavior regression, not a formality. Do not
      // re-pin without a deliberate decision.
      final date = DateTime(2026, 1, 15); // winter
      final got = [
        for (int day = 1; day <= 8; day++)
          WeatherEngine.weatherFor(
            sessionSeed: 'golden-session',
            dayCount: day,
            date: date,
          ).toString(),
      ];
      expect(got, [
        'DailyWeather(cloudy, cold, winter)',
        'DailyWeather(overcast, cold, winter)',
        'DailyWeather(storm, cold, winter)',
        'DailyWeather(storm, cool, winter)',
        'DailyWeather(clear, cold, winter)',
        'DailyWeather(clear, cold, winter)',
        'DailyWeather(fog, cool, winter)',
        'DailyWeather(clear, cold, winter)',
      ]);
    });
  });

  group('WeatherEngine invariants', () {
    test('snow never appears outside cold temps, across seasons and seeds', () {
      for (final seed in ['s1', 's2', 's3']) {
        for (int day = 1; day <= 400; day++) {
          final w = WeatherEngine.weatherFor(
            sessionSeed: seed,
            dayCount: day,
            // Walk the calendar so all four seasons appear.
            date: DateTime(2026, 1, 1).add(Duration(days: day)),
          );
          if (w.condition == WeatherCondition.snow) {
            expect(w.temp, TempBand.cold, reason: 'snow requires cold');
            expect(w.season, 'winter', reason: 'snow only weighted in winter');
          }
        }
      }
    });

    test('season mapping follows months', () {
      expect(WeatherEngine.seasonOf(DateTime(2026, 1, 10)), 'winter');
      expect(WeatherEngine.seasonOf(DateTime(2026, 12, 25)), 'winter');
      expect(WeatherEngine.seasonOf(DateTime(2026, 4, 1)), 'spring');
      expect(WeatherEngine.seasonOf(DateTime(2026, 7, 15)), 'summer');
      expect(WeatherEngine.seasonOf(DateTime(2026, 10, 3)), 'autumn');
    });

    test('prose and label never contain digits (words-only contract)', () {
      for (int day = 1; day <= 60; day++) {
        final w = WeatherEngine.weatherFor(
          sessionSeed: 'prose-check',
          dayCount: day,
          date: DateTime(2026, 1, 1).add(Duration(days: day * 6)),
        );
        expect(WeatherEngine.prose(w), isNot(matches(RegExp(r'\d'))));
        expect(WeatherEngine.label(w), isNot(matches(RegExp(r'\d'))));
      }
    });
  });

  group('WeatherEngine forecast & foreshadow', () {
    test('forecast made today is what tomorrow actually becomes', () {
      // The walk is prefix-stable and dayCount is derived from the calendar
      // date, so the (dayCount+1, clock+1day) forecast call and the real
      // arrival call are the same inputs — the foreshadowing can never lie.
      final start = DateTime(2026, 3, 10);
      for (int d = 1; d <= 40; d++) {
        final todayDate = start.add(Duration(days: d - 1));
        final forecast = WeatherEngine.weatherFor(
          sessionSeed: 'forecast-check',
          dayCount: d + 1,
          date: todayDate.add(const Duration(days: 1)),
        );
        final arrival = WeatherEngine.weatherFor(
          sessionSeed: 'forecast-check',
          dayCount: d + 1,
          date: start.add(Duration(days: d)),
        );
        expect(forecast, equals(arrival), reason: 'day $d forecast must hold');
      }
    });

    const mildClear = DailyWeather(
      condition: WeatherCondition.clear,
      temp: TempBand.mild,
      season: 'spring',
    );

    DailyWeather w(WeatherCondition c, [TempBand t = TempBand.mild]) =>
        DailyWeather(condition: c, temp: t, season: 'spring');

    test('no change → silent; minor cloud shuffle → silent', () {
      expect(WeatherEngine.foreshadow(mildClear, mildClear), isEmpty);
      expect(
        WeatherEngine.foreshadow(mildClear, w(WeatherCondition.cloudy)),
        isEmpty,
      );
      expect(
        WeatherEngine.foreshadow(w(WeatherCondition.cloudy), mildClear),
        isEmpty,
      );
    });

    test('incoming precipitation and fog produce a sign', () {
      expect(
        WeatherEngine.foreshadow(mildClear, w(WeatherCondition.storm)),
        contains('storm'),
      );
      expect(
        WeatherEngine.foreshadow(mildClear, w(WeatherCondition.rain)),
        contains('rain'),
      );
      expect(
        WeatherEngine.foreshadow(
          w(WeatherCondition.overcast),
          w(WeatherCondition.snow, TempBand.cold),
        ),
        contains('snow'),
      );
      expect(
        WeatherEngine.foreshadow(mildClear, w(WeatherCondition.fog)),
        contains('fog'),
      );
    });

    test('clearing after wet or grey weather produces a sign', () {
      expect(
        WeatherEngine.foreshadow(w(WeatherCondition.rain), mildClear),
        contains('clear'),
      );
      expect(
        WeatherEngine.foreshadow(w(WeatherCondition.overcast), mildClear),
        contains('clear'),
      );
      expect(
        WeatherEngine.foreshadow(
          w(WeatherCondition.storm),
          w(WeatherCondition.cloudy),
        ),
        contains('ease'),
      );
    });

    test('storm easing into rain reads as easing, not incoming rain', () {
      expect(
        WeatherEngine.foreshadow(
          w(WeatherCondition.storm),
          w(WeatherCondition.rain),
        ),
        contains('easing'),
      );
    });

    test('two-band temperature swing speaks; one band stays silent', () {
      expect(
        WeatherEngine.foreshadow(
          w(WeatherCondition.clear, TempBand.warm),
          w(WeatherCondition.clear, TempBand.cool),
        ),
        contains('colder'),
      );
      expect(
        WeatherEngine.foreshadow(
          w(WeatherCondition.clear, TempBand.cool),
          w(WeatherCondition.clear, TempBand.warm),
        ),
        contains('warmer'),
      );
      expect(
        WeatherEngine.foreshadow(
          w(WeatherCondition.clear, TempBand.mild),
          w(WeatherCondition.clear, TempBand.warm),
        ),
        isEmpty,
      );
    });

    test('foreshadow never contains digits (words-only contract)', () {
      for (final from in WeatherCondition.values) {
        for (final to in WeatherCondition.values) {
          for (final tf in TempBand.values) {
            for (final tt in TempBand.values) {
              final line = WeatherEngine.foreshadow(
                w(from, tf),
                w(to, tt),
              );
              expect(line, isNot(matches(RegExp(r'\d'))));
            }
          }
        }
      }
    });
  });

}
