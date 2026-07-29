// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

void main() {
  test('temperate matches historical season tables', () {
    expect(Biome.temperate.weights['winter'], [20, 20, 20, 10, 10, 2, 18]);
    expect(Biome.temperate.baseTemp['summer'], 3);
  });

  test('null biome weather equals temperate for same seed', () {
    const seed = 'session-gold-1';
    final date = DateTime.utc(2026, 7, 15);
    final a = WeatherEngine.weatherFor(
      sessionSeed: seed,
      dayCount: 12,
      date: date,
    );
    final b = WeatherEngine.weatherFor(
      sessionSeed: seed,
      dayCount: 12,
      date: date,
      biome: Biome.temperate,
    );
    expect(a.condition, b.condition);
    expect(a.temp, b.temp);
    expect(a.season, b.season);
  });

  test('desert never draws snow weight in summer', () {
    expect(Biome.desert.weights['summer']![6], 0);
  });

  test('validate rejects zero-sum seasons', () {
    final bad = Biome(
      id: 'bad',
      displayName: 'Bad',
      description: '',
      weights: {
        for (final s in kSeasons) s: [0, 0, 0, 0, 0, 0, 0],
      },
      baseTemp: {for (final s in kSeasons) s: 2},
    );
    expect(bad.validate(), isNotEmpty);
  });
}
