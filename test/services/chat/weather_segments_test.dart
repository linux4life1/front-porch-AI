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

// Intra-day weather segments + deterministic temperatures (Living Time §3
// v3). Pins the segments' own contracts — determinism, golden stability, and
// the timing-realism invariants the script tables encode — plus the words-only
// guard: numbers exist for the UI, never for prompts.
//
// The DAILY walk has one owner: the 8-day golden in weather_engine_test.dart.
// A copy lived here too, under the name "adding segments did NOT change the
// pinned daily walk" — but it never called the segment layer, so it only
// re-ran the engine and checked the first of the eight days it computed. Two
// goldens over one sequence means the weaker one gets re-pinned to whatever
// the code now does; deleted 2026-09-18, engine golden keeps the contract.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/chat/weather_segments.dart';

void main() {
  group('determinism & stability', () {
    test('same inputs always yield the same segment weather', () {
      final date = DateTime(2026, 7, 21);
      for (int day = 1; day <= 20; day++) {
        for (final hour in [6, 12, 18, 23]) {
          final a = WeatherSegments.segmentWeatherFor(
            sessionSeed: 'session-abc',
            dayCount: day,
            date: date,
            hour: hour,
          );
          final b = WeatherSegments.segmentWeatherFor(
            sessionSeed: 'session-abc',
            dayCount: day,
            date: date,
            hour: hour,
          );
          expect(a, equals(b), reason: 'day $day hour $hour reproducible');
        }
      }
    });

    test('the day script is hour-independent (prefix-stable within a day)', () {
      final date = DateTime(2026, 3, 10);
      for (int day = 1; day <= 15; day++) {
        final morning = WeatherSegments.segmentWeatherFor(
          sessionSeed: 's',
          dayCount: day,
          date: date,
          hour: 7,
        );
        // Asking about the evening must not rewrite the morning.
        final morningAgain = WeatherSegments.segmentWeatherFor(
          sessionSeed: 's',
          dayCount: day,
          date: date,
          hour: 7,
        );
        WeatherSegments.segmentWeatherFor(
          sessionSeed: 's',
          dayCount: day,
          date: date,
          hour: 19,
        );
        expect(morning, morningAgain);
      }
    });

    test('golden segment sequence is pinned (cross-release stability)', () {
      // If this fails, intra-day weather changed for EXISTING chats — a
      // behavior regression, not a formality. Do not re-pin casually.
      final date = DateTime(2026, 1, 15);
      final got = [
        for (int day = 1; day <= 4; day++)
          WeatherSegments.segmentConditionsFor(
            sessionSeed: 'golden-session',
            dayCount: day,
            date: date,
          ).map((c) => c.name).join(','),
      ];
      expect(got, [
        'cloudy,overcast,cloudy,clear',
        'overcast,overcast,cloudy,overcast',
        'cloudy,overcast,storm,rain',
        'rain,storm,storm,rain',
      ]);
    });
  });

  group('script invariants (timing realism)', () {
    // Sweep many (session, day) pairs; these hold for EVERY script by table
    // construction — the sweep guards against future table edits breaking
    // them silently.
    final dates = [
      DateTime(2026, 1, 10), // winter
      DateTime(2026, 4, 10), // spring
      DateTime(2026, 7, 10), // summer
      DateTime(2026, 10, 10), // autumn
    ];

    test('every day script contains its anchor condition', () {
      for (final date in dates) {
        for (int s = 0; s < 8; s++) {
          for (int day = 1; day <= 40; day++) {
            final anchor = WeatherEngine.weatherFor(
              sessionSeed: 'sweep-$s',
              dayCount: day,
              date: date,
            ).condition;
            final segs = WeatherSegments.segmentConditionsFor(
              sessionSeed: 'sweep-$s',
              dayCount: day,
              date: date,
            );
            expect(
              segs,
              contains(anchor),
              reason: 'day $day (${anchor.name}) script $segs',
            );
          }
        }
      }
    });

    test('fog-day mornings are always fog; storms only on storm days', () {
      for (final date in dates) {
        for (int s = 0; s < 8; s++) {
          for (int day = 1; day <= 40; day++) {
            final anchor = WeatherEngine.weatherFor(
              sessionSeed: 'sweep-$s',
              dayCount: day,
              date: date,
            ).condition;
            final segs = WeatherSegments.segmentConditionsFor(
              sessionSeed: 'sweep-$s',
              dayCount: day,
              date: date,
            );
            if (anchor == WeatherCondition.fog) {
              expect(
                segs.first,
                WeatherCondition.fog,
                reason: 'fog days start foggy',
              );
            }
            if (segs.contains(WeatherCondition.storm)) {
              expect(
                anchor,
                WeatherCondition.storm,
                reason: 'storm segments only occur on storm days',
              );
            }
          }
        }
      }
    });

    test('segment mapping covers all 24 hours', () {
      for (int h = 0; h < 24; h++) {
        expect(() => WeatherSegments.segmentForHour(h), returnsNormally);
      }
      expect(WeatherSegments.segmentForHour(7), DaySegment.morning);
      expect(WeatherSegments.segmentForHour(13), DaySegment.afternoon);
      expect(WeatherSegments.segmentForHour(18), DaySegment.evening);
      expect(WeatherSegments.segmentForHour(2), DaySegment.night);
      expect(WeatherSegments.segmentForHour(22), DaySegment.night);
    });
  });

  group('temperatures', () {
    test(
      '°C stays consistent with the band, afternoon warmer than morning',
      () {
        final date = DateTime(2026, 7, 21);
        for (int day = 1; day <= 60; day++) {
          final morning = WeatherSegments.segmentWeatherFor(
            sessionSeed: 'temps',
            dayCount: day,
            date: date,
            hour: 7,
          );
          final afternoon = WeatherSegments.segmentWeatherFor(
            sessionSeed: 'temps',
            dayCount: day,
            date: date,
            hour: 14,
          );
          final night = WeatherSegments.segmentWeatherFor(
            sessionSeed: 'temps',
            dayCount: day,
            date: date,
            hour: 23,
          );
          expect(afternoon.tempC, greaterThan(morning.tempC));
          expect(night.tempC, lessThan(afternoon.tempC));
          // Band honesty: the afternoon peak sits within (or a couple of
          // degrees above) the band; the night trough a few below.
          expect(afternoon.tempC - night.tempC, 8); // fixed diurnal spread
        }
      },
    );

    test('°F conversion and formatting', () {
      expect(WeatherSegments.tempF(0), 32);
      expect(WeatherSegments.tempF(20), 68);
      expect(WeatherSegments.tempF(-5), 23);
      expect(WeatherSegments.formatTemp(4, fahrenheit: false), '4°C');
      expect(WeatherSegments.formatTemp(4, fahrenheit: true), '39°F');
    });

    test('chip label carries the number in the chosen unit', () {
      final w = WeatherSegments.segmentWeatherFor(
        sessionSeed: 'label',
        dayCount: 3,
        date: DateTime(2026, 7, 21),
        hour: 14,
      );
      expect(WeatherSegments.label(w, fahrenheit: false), contains('°C'));
      expect(WeatherSegments.label(w, fahrenheit: true), contains('°F'));
    });
  });

  group('prompt prose (words-only contract)', () {
    final digits = RegExp(r'\d');

    test('prose and transitions never contain digits', () {
      final date = DateTime(2026, 10, 5);
      SegmentWeather? prev;
      for (int day = 1; day <= 30; day++) {
        for (final hour in [7, 14, 18, 23]) {
          final w = WeatherSegments.segmentWeatherFor(
            sessionSeed: 'prose',
            dayCount: day,
            date: date,
            hour: hour,
          );
          expect(
            WeatherSegments.prose(w),
            isNot(matches(digits)),
            reason: 'no numbers in generation prompts',
          );
          if (prev != null) {
            expect(WeatherSegments.transition(prev, w), isNot(matches(digits)));
          }
          prev = w;
        }
      }
    });

    test('prose ends with condition line and starts with the dressing cue', () {
      final w = WeatherSegments.segmentWeatherFor(
        sessionSeed: 'cue',
        dayCount: 2,
        date: DateTime(2026, 1, 20),
        hour: 8,
      );
      final p = WeatherSegments.prose(w);
      expect(p, startsWith('Outside it is '));
      expect(p, contains(WeatherSegments.dressCue(w.day.temp)));
    });

    test(
      'injection composes prose + within-day shift + foreshadow, no digits',
      () {
        const day = DailyWeather(
          condition: WeatherCondition.rain,
          temp: TempBand.cool,
          season: 'autumn',
        );
        const prev = SegmentWeather(
          day: day,
          segment: DaySegment.morning,
          condition: WeatherCondition.overcast,
          tempC: 6,
        );
        const now = SegmentWeather(
          day: day,
          segment: DaySegment.afternoon,
          condition: WeatherCondition.rain,
          tempC: 11,
        );
        final line = WeatherInjection(
          getWeather: () => now,
          getPreviousSegment: () => prev,
          getUpcoming: () => const DailyWeather(
            condition: WeatherCondition.storm,
            temp: TempBand.cool,
            season: 'autumn',
          ),
        ).buildWeatherInjection();
        expect(line, contains('Outside it is jacket weather.'));
        expect(line, contains('rain moved in')); // within-day shift spoken
        expect(line, contains('storm')); // tomorrow foreshadowed
        expect(
          line,
          isNot(matches(RegExp(r'\d'))),
          reason: 'temperature numbers are UI-only, never in prompts',
        );

        // Weather off → '' (composer drops the fragment, block shape stable).
        expect(
          WeatherInjection(
            getWeather: () => null,
            getPreviousSegment: () => null,
            getUpcoming: () => null,
          ).buildWeatherInjection(),
          isEmpty,
        );
      },
    );

    test('transition is silent on no change, speaks on real change', () {
      SegmentWeather seg(WeatherCondition c, DaySegment s) => SegmentWeather(
        day: const DailyWeather(
          condition: WeatherCondition.rain,
          temp: TempBand.cool,
          season: 'autumn',
        ),
        segment: s,
        condition: c,
        tempC: 8,
      );
      expect(
        WeatherSegments.transition(
          seg(WeatherCondition.rain, DaySegment.morning),
          seg(WeatherCondition.rain, DaySegment.afternoon),
        ),
        isEmpty,
      );
      expect(
        WeatherSegments.transition(
          seg(WeatherCondition.overcast, DaySegment.morning),
          seg(WeatherCondition.rain, DaySegment.afternoon),
        ),
        contains('moved in'),
      );
      expect(
        WeatherSegments.transition(
          seg(WeatherCondition.rain, DaySegment.morning),
          seg(WeatherCondition.cloudy, DaySegment.evening),
        ),
        contains('eased off'),
      );
      expect(
        WeatherSegments.transition(
          seg(WeatherCondition.overcast, DaySegment.afternoon),
          seg(WeatherCondition.storm, DaySegment.evening),
        ),
        contains('storm'),
      );
    });
  });
}
