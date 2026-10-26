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

// The Ambient Stage's weather mapping (docs/design/ambient-stage.md): every
// part of day, condition and temperature band resolves to layers the web
// paints from the wire, a neutral cell paints nothing, and the chat's own
// text stays readable over the tinted canvas on every theme in both modes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_gate.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/chat/weather_segments.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

const _dayparts = [
  'dawn',
  'morning',
  'late_morning',
  'afternoon',
  'evening',
  'night',
];

Iterable<SceneTokens> _cells({required bool dark}) sync* {
  for (final d in _dayparts) {
    for (final c in WeatherCondition.values) {
      for (final t in TempBand.values) {
        yield SceneSim.resolve(daypart: d, condition: c, temp: t, dark: dark);
      }
    }
  }
}

void main() {
  test('every cell resolves and echoes its inputs', () {
    var count = 0;
    for (final s in _cells(dark: true)) {
      count++;
      expect(_dayparts, contains(s.daypart));
      expect(WeatherCondition.values.map((c) => c.name), contains(s.condition));
      expect(TempBand.values.map((t) => t.name), contains(s.temp));
      for (final l in s.layers) {
        expect(l.alpha, greaterThan(0), reason: 'zero layers are dropped');
        expect(l.alpha, lessThanOrEqualTo(1));
      }
      expect(s.haze, inInclusiveRange(0, 1));
    }
    expect(
      count,
      _dayparts.length *
          WeatherCondition.values.length *
          TempBand.values.length,
    );
  });

  test('a clear, mild, late-morning scene paints nothing', () {
    final s = SceneSim.resolve(
      daypart: 'late_morning',
      condition: WeatherCondition.clear,
      temp: TempBand.mild,
      dark: true,
    );
    expect(s.layers, isEmpty);
    expect(s.haze, 0);
    expect(s.compositeOver(AppColors.background), AppColors.background);
  });

  test('a period this build does not know paints only the weather', () {
    final known = SceneSim.resolve(
      daypart: 'late_morning',
      condition: WeatherCondition.rain,
      temp: TempBand.cold,
      dark: true,
    );
    final unknown = SceneSim.resolve(
      daypart: 'second_breakfast',
      condition: WeatherCondition.rain,
      temp: TempBand.cold,
      dark: true,
    );
    expect(unknown.layers, known.layers);
    expect(unknown.haze, known.haze);
  });

  test('storm darkens most, night washes strongest, fog hazes most', () {
    // On a near-black ground every wash lightens, so darkness is judged on
    // a mid grey, per condition at one part of day; the part of day by the
    // weight of its wash.
    const ground = Color(0xFF808080);
    double lum(SceneTokens s) => s.compositeOver(ground).computeLuminance();
    SceneTokens at(WeatherCondition c) => SceneSim.resolve(
      daypart: 'late_morning',
      condition: c,
      temp: TempBand.mild,
      dark: true,
    );
    final darkest = WeatherCondition.values.reduce(
      (a, b) => lum(at(a)) <= lum(at(b)) ? a : b,
    );
    expect(darkest, WeatherCondition.storm);
    expect(lum(at(WeatherCondition.clear)), ground.computeLuminance());
    final strongest = kSceneDaypartWash.entries.reduce(
      (a, b) => a.value.alpha >= b.value.alpha ? a : b,
    );
    expect(strongest.key, 'night');
    final haziest = _cells(
      dark: true,
    ).reduce((a, b) => a.haze >= b.haze ? a : b);
    expect(haziest.condition, 'fog');
  });

  test('light mode scales every wash down', () {
    for (final d in _dayparts) {
      for (final c in WeatherCondition.values) {
        for (final t in TempBand.values) {
          final dark = SceneSim.resolve(
            daypart: d,
            condition: c,
            temp: t,
            dark: true,
          );
          final light = SceneSim.resolve(
            daypart: d,
            condition: c,
            temp: t,
            dark: false,
          );
          expect(light.layers.length, dark.layers.length);
          for (var i = 0; i < dark.layers.length; i++) {
            expect(light.layers[i].color, dark.layers[i].color);
            expect(
              light.layers[i].alpha,
              closeTo(dark.layers[i].alpha * kSceneLightModeScale, 1e-9),
            );
          }
          expect(light.haze, closeTo(dark.haze * kSceneLightModeScale, 1e-9));
        }
      }
    }
  });

  test('the chat\'s own text reads over the tinted canvas on every theme', () {
    // The stage paints behind the bubbles; what sits on the bare canvas is
    // the theme's own text, so that is what must survive every cell.
    for (final theme in AppThemeId.values) {
      for (final dark in [true, false]) {
        final p = dark ? theme.palettes.dark : theme.palettes.light;
        // High Contrast promises AAA (7:1); every other theme AA (4.5:1).
        final floor = AppearanceSettings.accentMinRatio(theme);
        for (final s in _cells(dark: dark)) {
          final ground = s.compositeOver(p.background);
          expect(
            contrastRatio(p.textPrimary, ground),
            greaterThanOrEqualTo(floor),
            reason:
                '${theme.label} ${dark ? 'dark' : 'light'}: '
                '${s.daypart}/${s.condition}/${s.temp} leaves primary text '
                'at ${contrastRatio(p.textPrimary, ground).toStringAsFixed(2)}',
          );
        }
      }
    }
  });

  test('the wire is CSS strings for both modes, without maths', () {
    SceneTokens at(bool dark) => SceneSim.resolve(
      daypart: 'night',
      condition: WeatherCondition.fog,
      temp: TempBand.cold,
      dark: dark,
    );
    final w = SceneTokens.wireOf(dark: at(true), light: at(false));
    expect(w['daypart'], 'night');
    expect(w['condition'], 'fog');
    expect(w['temp'], 'cold');
    final css = RegExp(r'^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$');
    for (final dark in [true, false]) {
      final s = at(dark);
      final m = w[dark ? 'dark' : 'light']! as Map<String, Object>;
      expect(
        m.keys,
        // `paints` is the moving weather's colours for the mode
        // (scene_effects_test pins them).
        unorderedEquals(['layers', 'haze', 'hazeCentre', 'hazeEdge', 'paints']),
      );
      final layers = (m['layers']! as List).cast<String>();
      expect(layers.length, s.layers.length);
      for (final l in [
        ...layers,
        m['hazeCentre']! as String,
        m['hazeEdge']! as String,
      ]) {
        expect(l, matches(css), reason: l);
      }
      expect(m['haze'], s.haze);
      // Translucent layers travel with their alpha.
      expect(layers.first, startsWith('rgba('));
    }
    // The two modes are different washes of the same scene.
    expect(
      (w['light']! as Map)['layers'],
      isNot((w['dark']! as Map)['layers']),
    );
  });

  group('the gate', () {
    const day = DailyWeather(
      condition: WeatherCondition.rain,
      temp: TempBand.cold,
      season: 'autumn',
    );
    const segment = SegmentWeather(
      day: day,
      segment: DaySegment.evening,
      condition: WeatherCondition.storm,
      tempC: 4,
    );

    test('Off paints nothing, even with weather', () {
      expect(
        SceneGate.resolve(
          scene: AmbientScene.off,
          day: day,
          segment: segment,
          daypart: 'evening',
          dark: true,
          theme: AppThemeId.porch,
          sessionSeed: 'chat',
          dayCount: 3,
          pauseWhileGenerating: true,
        ),
        isNull,
      );
    });

    test('Tint without day weather paints nothing', () {
      expect(
        SceneGate.resolve(
          scene: AmbientScene.tint,
          day: null,
          daypart: 'evening',
          dark: true,
          theme: AppThemeId.porch,
          sessionSeed: 'chat',
          dayCount: 3,
          pauseWhileGenerating: true,
        ),
        isNull,
      );
    });

    test('Tint shows the segment, else the day, in the asked mode', () {
      for (final dark in [true, false]) {
        final withSegment = SceneGate.resolve(
          scene: AmbientScene.tint,
          day: day,
          segment: segment,
          daypart: 'evening',
          dark: dark,
          theme: AppThemeId.porch,
          sessionSeed: 'chat',
          dayCount: 3,
          pauseWhileGenerating: true,
        )!;
        expect(withSegment.condition, 'storm');
        expect(withSegment.temp, 'cold');
        expect(withSegment.daypart, 'evening');
        expect(withSegment.dark, dark);
        final dayOnly = SceneGate.resolve(
          scene: AmbientScene.tint,
          day: day,
          daypart: 'evening',
          dark: dark,
          theme: AppThemeId.porch,
          sessionSeed: 'chat',
          dayCount: 3,
          pauseWhileGenerating: true,
        )!;
        expect(dayOnly.condition, 'rain');
        expect(dayOnly.dark, dark);
        expect(
          dayOnly,
          SceneSim.resolve(
            daypart: 'evening',
            condition: WeatherCondition.rain,
            temp: TempBand.cold,
            dark: dark,
            seed: sceneSeed(
              sessionSeed: 'chat',
              dayCount: 3,
              daypart: 'evening',
              condition: 'rain',
            ),
          ),
        );
      }
    });
  });

  test('tokens are a value type', () {
    SceneTokens make() => SceneSim.resolve(
      daypart: 'evening',
      condition: WeatherCondition.snow,
      temp: TempBand.cool,
      dark: true,
    );
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(
      make(),
      isNot(
        SceneSim.resolve(
          daypart: 'evening',
          condition: WeatherCondition.snow,
          temp: TempBand.cool,
          dark: false,
        ),
      ),
    );
  });

  test('every wash in the palette is a solid colour with a sane alpha', () {
    for (final w in [...kSceneDaypartWash.values, ...kSceneTempCast.values]) {
      expect(w.alpha, inInclusiveRange(0, 0.5));
      expect(w.color.a, 1.0, reason: 'washes are solid; the stage adds alpha');
    }
    for (final c in kSceneConditionWash.values) {
      expect(c.wash.alpha, inInclusiveRange(0, 0.5));
      expect(c.darken, inInclusiveRange(0, 0.5));
      expect(c.haze, inInclusiveRange(0, 1));
    }
  });
}
