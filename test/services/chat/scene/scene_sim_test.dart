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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
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

  test('a stormy night is the darkest scene and fog the haziest', () {
    final ground = AppThemePalettes.porch.dark.background;
    double lum(SceneTokens s) => s.compositeOver(ground).computeLuminance();
    final all = _cells(dark: true).toList();
    final darkest = all.reduce((a, b) => lum(a) <= lum(b) ? a : b);
    expect(darkest.daypart, 'night');
    expect(darkest.condition, 'storm');
    final haziest = all.reduce((a, b) => a.haze >= b.haze ? a : b);
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
        for (final s in _cells(dark: dark)) {
          final ground = s.compositeOver(p.background);
          expect(
            contrastRatio(p.textPrimary, ground),
            greaterThanOrEqualTo(4.5),
            reason:
                '${theme.label} ${dark ? 'dark' : 'light'}: '
                '${s.daypart}/${s.condition}/${s.temp} leaves primary text '
                'at ${contrastRatio(p.textPrimary, ground).toStringAsFixed(2)}',
          );
        }
      }
    }
  });

  test('the wire is CSS strings the web can paint without maths', () {
    final s = SceneSim.resolve(
      daypart: 'night',
      condition: WeatherCondition.fog,
      temp: TempBand.cold,
      dark: true,
    );
    final w = s.toWire();
    expect(w['daypart'], 'night');
    expect(w['condition'], 'fog');
    expect(w['temp'], 'cold');
    final layers = (w['layers'] as List).cast<String>();
    expect(layers.length, s.layers.length);
    final css = RegExp(r'^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$');
    for (final l in [
      ...layers,
      w['hazeCentre'] as String,
      w['hazeEdge'] as String,
    ]) {
      expect(l, matches(css), reason: l);
    }
    expect(w['haze'], s.haze);
    // Translucent layers travel with their alpha.
    expect(layers.first, startsWith('rgba('));
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
