// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pinned weather sequences for EVERY built-in biome (living-worlds.md §7 —
// closes the "per-built-in pinned goldens" test-debt row). The temperate pin
// in weather_engine_test.dart fences only the default climate; these fence
// the other six, so engine work (e.g. Phase 2's extreme temperature bands)
// cannot silently rewrite the weather history of ANY shipped climate.
//
// If one of these fails, the engine's output changed for EXISTING chats
// using that climate — a behavior regression, not a formality. Do not
// re-pin without a deliberate decision (same contract as the temperate pin).
//
// Fixture: sessionSeed 'golden-session', 8 days, mid-January and mid-July
// (both hemispheres of each biome's seasonality — e.g. mediterranean's
// inverted precipitation only shows against both dates).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

/// id → {season label → expected 8-day sequence}.
const Map<String, Map<String, List<String>>> kBiomePins = {
  'temperate': {
    'winter': [
      'DailyWeather(cloudy, cold, winter)',
      'DailyWeather(overcast, cold, winter)',
      'DailyWeather(storm, cold, winter)',
      'DailyWeather(storm, cool, winter)',
      'DailyWeather(clear, cold, winter)',
      'DailyWeather(clear, cold, winter)',
      'DailyWeather(fog, cool, winter)',
      'DailyWeather(clear, cold, winter)',
    ],
    'summer': [
      'DailyWeather(clear, warm, summer)',
      'DailyWeather(cloudy, warm, summer)',
      'DailyWeather(rain, warm, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(clear, warm, summer)',
      'DailyWeather(clear, warm, summer)',
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(clear, warm, summer)',
    ],
  },
  'rainforest': {
    'winter': [
      'DailyWeather(overcast, mild, winter)',
      'DailyWeather(overcast, mild, winter)',
      'DailyWeather(rain, mild, winter)',
      'DailyWeather(rain, warm, winter)',
      'DailyWeather(cloudy, mild, winter)',
      'DailyWeather(cloudy, mild, winter)',
      'DailyWeather(fog, warm, winter)',
      'DailyWeather(cloudy, mild, winter)',
    ],
    'summer': [
      'DailyWeather(overcast, warm, summer)',
      'DailyWeather(fog, warm, summer)',
      'DailyWeather(rain, warm, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(clear, warm, summer)',
      'DailyWeather(clear, warm, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(clear, warm, summer)',
    ],
  },
  'desert': {
    'winter': [
      'DailyWeather(clear, cool, winter)',
      'DailyWeather(clear, cool, winter)',
      'DailyWeather(cloudy, cool, winter)',
      'DailyWeather(cloudy, mild, winter)',
      'DailyWeather(clear, cool, winter)',
      'DailyWeather(clear, cool, winter)',
      'DailyWeather(clear, mild, winter)',
      'DailyWeather(clear, cool, winter)',
    ],
    'summer': [
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
    ],
  },
  'continental': {
    'winter': [
      'DailyWeather(overcast, cold, winter)',
      'DailyWeather(fog, cold, winter)',
      'DailyWeather(snow, cold, winter)',
      'DailyWeather(rain, cool, winter)',
      'DailyWeather(clear, cold, winter)',
      'DailyWeather(clear, cold, winter)',
      'DailyWeather(rain, cool, winter)',
      'DailyWeather(clear, cold, winter)',
    ],
    'summer': [
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(storm, hot, summer)',
      'DailyWeather(storm, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(clear, hot, summer)',
    ],
  },
  'tropical': {
    'winter': [
      'DailyWeather(cloudy, warm, winter)',
      'DailyWeather(cloudy, warm, winter)',
      'DailyWeather(rain, warm, winter)',
      'DailyWeather(rain, hot, winter)',
      'DailyWeather(clear, warm, winter)',
      'DailyWeather(clear, warm, winter)',
      'DailyWeather(overcast, hot, winter)',
      'DailyWeather(clear, warm, winter)',
    ],
    'summer': [
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(overcast, hot, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(rain, hot, summer)',
      'DailyWeather(clear, hot, summer)',
    ],
  },
  'mediterranean': {
    'winter': [
      'DailyWeather(cloudy, cool, winter)',
      'DailyWeather(overcast, cool, winter)',
      'DailyWeather(rain, cool, winter)',
      'DailyWeather(rain, mild, winter)',
      'DailyWeather(clear, cool, winter)',
      'DailyWeather(clear, cool, winter)',
      'DailyWeather(fog, mild, winter)',
      'DailyWeather(clear, cool, winter)',
    ],
    'summer': [
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(cloudy, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
      'DailyWeather(clear, hot, summer)',
    ],
  },
  'highland': {
    'winter': [
      'DailyWeather(overcast, cold, winter)',
      'DailyWeather(fog, cold, winter)',
      'DailyWeather(snow, cold, winter)',
      'DailyWeather(rain, cool, winter)',
      'DailyWeather(clear, cold, winter)',
      'DailyWeather(clear, cold, winter)',
      'DailyWeather(rain, cool, winter)',
      'DailyWeather(clear, cold, winter)',
    ],
    'summer': [
      'DailyWeather(cloudy, mild, summer)',
      'DailyWeather(cloudy, mild, summer)',
      'DailyWeather(rain, mild, summer)',
      'DailyWeather(rain, warm, summer)',
      'DailyWeather(clear, mild, summer)',
      'DailyWeather(clear, mild, summer)',
      'DailyWeather(overcast, warm, summer)',
      'DailyWeather(clear, mild, summer)',
    ],
  },
};

void main() {
  group('per-biome pinned sequences (cross-release stability)', () {
    for (final entry in kBiomePins.entries) {
      final id = entry.key;
      for (final season in entry.value.entries) {
        test('$id / ${season.key}', () {
          final biome = Biome.builtInById(id);
          expect(biome, isNotNull, reason: 'built-in "$id" must exist');
          final date = season.key == 'winter'
              ? DateTime(2026, 1, 15)
              : DateTime(2026, 7, 15);
          final got = [
            for (int day = 1; day <= 8; day++)
              WeatherEngine.weatherFor(
                sessionSeed: 'golden-session',
                dayCount: day,
                date: date,
                biome: biome,
              ).toString(),
          ];
          expect(got, entry.value[season.key]);
        });
      }
    }

    test('temperate pin matches the null-biome pin (identity)', () {
      // The temperate map above must equal the engine's null-biome output —
      // the same identity the weather_engine_test golden asserts, tied here
      // so the two pin files can never drift apart unnoticed.
      final got = [
        for (int day = 1; day <= 8; day++)
          WeatherEngine.weatherFor(
            sessionSeed: 'golden-session',
            dayCount: day,
            date: DateTime(2026, 1, 15),
          ).toString(),
      ];
      expect(got, kBiomePins['temperate']!['winter']);
    });
  });
}
