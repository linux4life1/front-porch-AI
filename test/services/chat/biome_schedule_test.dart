// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/biome_schedule.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';
import 'package:front_porch_ai/services/chat/weather_segments.dart';

void main() {
  group('BiomeSchedule', () {
    test('biomeAt uses world default before any span', () {
      final s = BiomeSchedule(
        worldDefault: Biome.desert,
        spans: [
          BiomeSpanEntry(effectiveFromDay: 5, biome: Biome.rainforest),
        ],
      );
      expect(s.biomeAt(1).id, 'desert');
      expect(s.biomeAt(4).id, 'desert');
      expect(s.biomeAt(5).id, 'rainforest');
      expect(s.biomeAt(99).id, 'rainforest');
    });

    test('isSpanStart only on effective_from_day', () {
      final s = BiomeSchedule(
        spans: [
          BiomeSpanEntry(effectiveFromDay: 3, biome: Biome.desert),
          BiomeSpanEntry(effectiveFromDay: 10, biome: Biome.highland),
        ],
      );
      expect(s.isSpanStart(1), isFalse);
      expect(s.isSpanStart(3), isTrue);
      expect(s.isSpanStart(4), isFalse);
      expect(s.isSpanStart(10), isTrue);
    });

    test('changeover keeps days before boundary byte-identical', () {
      final date = DateTime(2026, 1, 15);
      const seed = 'span-golden';
      final schedule = BiomeSchedule(
        worldDefault: Biome.temperate,
        spans: [
          BiomeSpanEntry(effectiveFromDay: 5, biome: Biome.desert),
        ],
      );

      for (var day = 1; day < 5; day++) {
        final withSpan = WeatherEngine.weatherFor(
          sessionSeed: seed,
          dayCount: day,
          date: date,
          biomeAtDay: schedule.biomeAt,
        );
        final temperateOnly = WeatherEngine.weatherFor(
          sessionSeed: seed,
          dayCount: day,
          date: date,
          biome: Biome.temperate,
        );
        expect(withSpan, equals(temperateOnly), reason: 'day $day pre-switch');
      }

      final day5span = WeatherEngine.weatherFor(
        sessionSeed: seed,
        dayCount: 5,
        date: date,
        biomeAtDay: schedule.biomeAt,
      );
      final day5temp = WeatherEngine.weatherFor(
        sessionSeed: seed,
        dayCount: 5,
        date: date,
        biome: Biome.temperate,
      );
      // After switch, desert tables may diverge from temperate.
      // Not required to differ every seed, but schedule path must be stable.
      expect(
        WeatherEngine.weatherFor(
          sessionSeed: seed,
          dayCount: 5,
          date: date,
          biomeAtDay: schedule.biomeAt,
        ),
        equals(day5span),
      );
      // Document that day 5 can differ once desert is active.
      expect(day5span.condition, isNotNull);
      expect(day5temp.condition, isNotNull);
    });
  });

  group('foreshadow suppress on span start', () {
    test('WeatherInjection skips foreshadow when suppress is true', () {
      final day = DailyWeather(
        condition: WeatherCondition.clear,
        temp: TempBand.mild,
        season: 'summer',
      );
      final segment = SegmentWeather(
        day: day,
        segment: DaySegment.afternoon,
        condition: WeatherCondition.clear,
        tempC: 22,
      );
      final tomorrow = DailyWeather(
        condition: WeatherCondition.storm,
        temp: TempBand.mild,
        season: 'summer',
      );

      final withForeshadow = WeatherInjection(
        getWeather: () => segment,
        getPreviousSegment: () => null,
        getUpcoming: () => tomorrow,
      ).buildWeatherInjection();
      expect(withForeshadow, contains('storm'));

      final suppressed = WeatherInjection(
        getWeather: () => segment,
        getPreviousSegment: () => null,
        getUpcoming: () => tomorrow,
        suppressForeshadow: () => true,
      ).buildWeatherInjection();
      expect(suppressed, isNot(contains('storm')));
    });
  });

  group('diurnalAmplitude', () {
    test('temperate amplitude leaves °C unchanged vs null biome', () {
      final date = DateTime(2026, 1, 15);
      final a = WeatherSegments.segmentWeatherFor(
        sessionSeed: 'golden-session',
        dayCount: 1,
        date: date,
        hour: 14,
      );
      final b = WeatherSegments.segmentWeatherFor(
        sessionSeed: 'golden-session',
        dayCount: 1,
        date: date,
        hour: 14,
        biome: Biome.temperate,
      );
      expect(a.tempC, equals(b.tempC));
      expect(a.condition, equals(b.condition));
    });

    test('desert has larger day-night swing than temperate', () {
      final date = DateTime(2026, 7, 1);
      int swing(Biome biome) {
        final afternoon = WeatherSegments.segmentWeatherFor(
          sessionSeed: 'amp-test',
          dayCount: 3,
          date: date,
          hour: 14,
          biome: biome,
        );
        final night = WeatherSegments.segmentWeatherFor(
          sessionSeed: 'amp-test',
          dayCount: 3,
          date: date,
          hour: 23,
          biome: biome,
        );
        return (afternoon.tempC - night.tempC).abs();
      }

      expect(swing(Biome.desert), greaterThan(swing(Biome.temperate)));
    });
  });
}
