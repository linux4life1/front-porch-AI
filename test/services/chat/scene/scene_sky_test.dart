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

// The story-clock sky (docs/design/ambient-stage.md, `scene_sky.dart`):
// the six period washes blend by the minute and wrap across midnight, the
// sun and moon ride an arc and are null below the horizon, the stars come
// out after sunset, a clock jump sweeps forward on an animated stage and
// snaps on a still one, and the gate places the sky from the clock. The
// shared vectors (test/fixtures/ambient/scene_sky_vectors.json) pin the
// numbers the web port reproduces.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_gate.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sky.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:front_porch_ai/ui/theme/scene_palette.dart';

final Map<String, dynamic> _vectors =
    jsonDecode(
          File(
            'test/fixtures/ambient/scene_sky_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Matcher _near(num v) => closeTo(v, 1e-9);

void main() {
  group('wash blend', () {
    test('each stop is the period wash at its representative minute', () {
      final byKey = {for (final s in kSceneSkyStops) s.at: s};
      expect(byKey.keys, [360, 540, 690, 870, 1110, 1350]);
      for (final s in kSceneSkyStops) {
        final w = skyWashAt(s.at.toDouble());
        expect(w.alpha, _near(s.alpha), reason: 'at ${s.at}');
        if (s.alpha > 0) expect(w.color, s.color, reason: 'at ${s.at}');
      }
    });

    test('halfway between two stops sits halfway in alpha', () {
      // dawn (0.14) to morning (0.08) over 360..540: smoothstep(0.5) = 0.5.
      expect(skyWashAt(450).alpha, _near(0.11));
    });

    test('wraps from night back to dawn across midnight', () {
      final late = skyWashAt(1439);
      final early = skyWashAt(0);
      expect(late.alpha, greaterThan(0.3));
      expect(early.alpha, lessThan(late.alpha));
      expect(early.alpha, greaterThan(skyWashAt(300).alpha));
    });

    test('a zero-alpha stop keeps its neighbour\'s hue', () {
      // late_morning has no wash; the blend toward it keeps morning's hue
      // and only the alpha goes to zero.
      final w = skyWashAt(600);
      expect(
        w.color.toARGB32(),
        kSceneDaypartWash['morning']!.color.toARGB32(),
      );
      expect(w.alpha, lessThan(kSceneDaypartWash['morning']!.alpha));
    });
  });

  group('sun, moon, stars, horizon', () {
    test('the sun is up between sunrise and sunset and peaks midway', () {
      expect(skyArcAt(300, rise: kSceneSunrise, set: kSceneSunset), isNull);
      final noon = skyArcAt(735, rise: kSceneSunrise, set: kSceneSunset)!;
      expect(noon.p, _near(0.5));
      expect(noon.alt, _near(1));
      expect(noon.y, lessThan(0.2));
      expect(skyArcAt(1200, rise: kSceneSunrise, set: kSceneSunset), isNull);
    });

    test('the moon crosses midnight', () {
      expect(skyArcAt(1000, rise: kSceneMoonrise, set: kSceneMoonset), isNull);
      final late = skyArcAt(1400, rise: kSceneMoonrise, set: kSceneMoonset)!;
      final early = skyArcAt(100, rise: kSceneMoonrise, set: kSceneMoonset)!;
      expect(early.p, greaterThan(late.p));
      expect(early.x, greaterThan(late.x));
    });

    test('stars come out after sunset and go in before dawn', () {
      expect(starVisibilityAt(800), 0);
      expect(starVisibilityAt(kSceneSunset.toDouble()), 0);
      expect(starVisibilityAt(1185), _near(0.5));
      expect(starVisibilityAt(1300), 1);
      expect(starVisibilityAt(100), 1);
      expect(starVisibilityAt(345), _near(0.5));
      expect(starVisibilityAt(400), 0);
    });

    test('the horizon glows at dawn and at dusk, not at noon', () {
      expect(horizonGlowAt(380), (strength: 1.0, dawn: true));
      expect(horizonGlowAt(1100), (strength: 1.0, dawn: false));
      expect(horizonGlowAt(735).strength, 0);
    });

    test('the moon is new on the epoch and full a fortnight later', () {
      expect(moonPhaseFor(DateTime.utc(2000, 1, 6, 18, 14)), 0);
      expect(
        moonPhaseFor(DateTime.utc(2000, 1, 21, 4, 40)),
        closeTo(0.5, 0.02),
      );
      expect(
        moonPhaseFor(DateTime.utc(1999, 12, 22, 17, 31)),
        closeTo(0.5, 0.02),
      );
    });

    test('the star field is scattered the same way every time', () {
      final a = scatterStars(kSceneStarSeed, kSceneStarCount);
      final b = scatterStars(kSceneStarSeed, kSceneStarCount);
      expect(a.length, kSceneStarCount);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].y, lessThanOrEqualTo(kSceneStarBand));
      }
    });
  });

  group('cover', () {
    test('thick weather veils the disc and the stars but never hides them', () {
      for (final c in WeatherCondition.values) {
        final sky = SceneSky.resolve(
          minute: 0,
          moonPhase: 0,
          condition: c.name,
        );
        expect(sky.disc, greaterThan(0), reason: c.name);
        expect(sky.disc, lessThanOrEqualTo(1), reason: c.name);
        expect(sky.stars, greaterThanOrEqualTo(0), reason: c.name);
      }
      expect(
        SceneSky.resolve(minute: 0, moonPhase: 0, condition: 'clear').veil,
        0,
      );
      expect(
        SceneSky.resolve(minute: 0, moonPhase: 0, condition: 'storm').veil,
        greaterThan(
          SceneSky.resolve(minute: 0, moonPhase: 0, condition: 'cloudy').veil,
        ),
      );
    });
  });

  group('motion', () {
    test('a sweep runs forward through the day and lands on the minute', () {
      final m = SceneSkyMotion(870)..retarget(360, sweep: true);
      expect(m.sweeping, isTrue);
      m.advance(0.9);
      // Forward: past midnight, never backwards through the afternoon.
      expect(m.shown, anyOf(greaterThan(870), lessThan(360)));
      m.advance(kSceneSweepSeconds);
      expect(m.sweeping, isFalse);
      expect(m.shown, 360);
      expect(m.target, 360);
    });

    test('a still stage snaps', () {
      final m = SceneSkyMotion(870)..retarget(360, sweep: false);
      expect(m.sweeping, isFalse);
      expect(m.shown, 360);
    });

    test('the same minute again is a no-op mid-sweep', () {
      final m = SceneSkyMotion(870)..retarget(360, sweep: true);
      m.advance(0.3);
      final shown = m.shown;
      m.retarget(360, sweep: true);
      expect(m.shown, shown);
      expect(m.sweeping, isTrue);
    });

    test('time runs on through advance for the twinkle', () {
      final m = SceneSkyMotion(0)
        ..advance(0.5)
        ..advance(0.25);
      expect(m.time, _near(0.75));
    });
  });

  group('tokens and gate', () {
    test('SceneSim places the sky at the period\'s representative minute '
        'without a clock, and at the clock\'s minute with one', () {
      final noClock = SceneSim.resolve(
        daypart: 'evening',
        condition: WeatherCondition.clear,
        temp: TempBand.mild,
        dark: true,
      );
      expect(noClock.sky?.minute, 1110);
      final clock = SceneSim.resolve(
        daypart: 'evening',
        condition: WeatherCondition.clear,
        temp: TempBand.mild,
        dark: true,
        minute: 1234,
        moonPhase: 0.25,
      );
      expect(clock.sky?.minute, 1234);
      expect(clock.sky?.moonPhase, 0.25);
      expect(clock, isNot(equals(noClock)));
    });

    test('the gate hands the clock through', () {
      final day = DailyWeather(
        condition: WeatherCondition.cloudy,
        temp: TempBand.cool,
        season: 'autumn',
      );
      final tokens = SceneGate.resolve(
        level: AmbientScene.tint,
        day: day,
        daypart: 'night',
        dark: true,
        minute: 1400,
        moonPhase: 0.9,
      )!;
      expect(tokens.sky, isNotNull);
      expect(tokens.sky!.minute, 1400);
      expect(tokens.sky!.moonPhase, 0.9);
      expect(tokens.sky!.disc, kSceneSkyCover['cloudy']!.disc);
    });

    test('a scene with a sky moves at Tint and effects even when clear', () {
      final clear = SceneSim.resolve(
        daypart: 'night',
        condition: WeatherCondition.clear,
        temp: TempBand.mild,
        dark: true,
        level: SceneLevel.effects,
      );
      expect(clear.hasEffects, isFalse);
      expect(clear.hasMotion, isTrue);
      final tint = SceneSim.resolve(
        daypart: 'night',
        condition: WeatherCondition.clear,
        temp: TempBand.mild,
        dark: true,
      );
      expect(tint.hasMotion, isFalse);
    });

    test('the wire carries the sky and each mode\'s sky paints', () {
      SceneTokens at(bool dark) => SceneSim.resolve(
        daypart: 'dawn',
        condition: WeatherCondition.rain,
        temp: TempBand.mild,
        dark: dark,
        minute: 380,
        moonPhase: 0.1,
      );
      final wire = SceneTokens.wireOf(dark: at(true), light: at(false));
      final sky = wire['sky'] as Map;
      expect(sky['minute'], 380);
      expect(sky['moonPhase'], 0.1);
      expect(sky['disc'], kSceneSkyCover['rain']!.disc);
      expect(sky['stars'], kSceneSkyCover['rain']!.stars);
      // The mode maps keep the keys they shipped with; the sky's colours
      // ride on the sky itself.
      expect((wire['dark'] as Map).containsKey('sky'), isFalse);
      final dark = sky['dark'] as Map;
      final light = sky['light'] as Map;
      expect(dark['scale'], 1.0);
      expect(light['scale'], kSceneLightModeScale);
      expect((dark['stops'] as List).length, 6);
      expect((dark['stops'] as List).first, {
        'at': 360,
        'colour': '#f2a07b',
        'alpha': 0.14,
      });
      expect(dark['star'], isNot(light['star']));
      expect(dark['sunHigh'], '#fff0c8');
    });
  });

  group('shared vectors', () {
    test('wash, arcs, stars and horizon match the fixture', () {
      for (final cell in _vectors['minutes'] as List) {
        final m = (cell['minute'] as num).toDouble();
        final wash = skyWashAt(m);
        final expected = cell['wash'] as Map;
        expect(wash.color.r * 255, closeTo(expected['r'] as num, 1e-6));
        expect(wash.color.g * 255, closeTo(expected['g'] as num, 1e-6));
        expect(wash.color.b * 255, closeTo(expected['b'] as num, 1e-6));
        expect(wash.alpha, closeTo(expected['alpha'] as num, 1e-9));
        for (final (name, rise, set) in [
          ('sun', kSceneSunrise, kSceneSunset),
          ('moon', kSceneMoonrise, kSceneMoonset),
        ]) {
          final arc = skyArcAt(m, rise: rise, set: set);
          final want = cell[name] as Map?;
          if (want == null) {
            expect(arc, isNull, reason: '$name at $m');
          } else {
            expect(arc!.p, closeTo(want['p'] as num, 1e-9));
            expect(arc.x, closeTo(want['x'] as num, 1e-9));
            expect(arc.y, closeTo(want['y'] as num, 1e-9));
            expect(arc.alt, closeTo(want['alt'] as num, 1e-9));
          }
        }
        expect(starVisibilityAt(m), closeTo(cell['stars'] as num, 1e-9));
        final glow = horizonGlowAt(m);
        expect(
          glow.strength,
          closeTo((cell['horizon'] as Map)['strength'] as num, 1e-9),
        );
        expect(glow.dawn, (cell['horizon'] as Map)['dawn']);
      }
    });

    test('the star field, the twinkle, the moon and a sweep match', () {
      final stars = scatterStars(kSceneStarSeed, 5);
      final field = _vectors['starField'] as List;
      for (var i = 0; i < 5; i++) {
        final want = field[i] as Map;
        expect(stars[i].x, closeTo(want['x'] as num, 1e-12));
        expect(stars[i].y, closeTo(want['y'] as num, 1e-12));
        expect(stars[i].size, closeTo(want['size'] as num, 1e-12));
        expect(stars[i].alpha, closeTo(want['alpha'] as num, 1e-12));
        expect(stars[i].phase, closeTo(want['phase'] as num, 1e-12));
        expect(stars[i].speed, closeTo(want['speed'] as num, 1e-12));
      }
      expect(
        starTwinkle(stars.first, 2.5),
        closeTo(_vectors['twinkle'] as num, 1e-12),
      );
      for (final p in _vectors['moonPhase'] as List) {
        expect(
          moonPhaseFor(DateTime.parse(p['iso'] as String)),
          closeTo(p['phase'] as num, 1e-12),
        );
      }
      final sweep = _vectors['sweep'] as Map;
      final m = SceneSkyMotion(sweep['from'] as int)
        ..retarget(sweep['to'] as int, sweep: true);
      for (final step in sweep['steps'] as List) {
        m.advance((step['after'] as num).toDouble());
        expect(m.shown, closeTo(step['shown'] as num, 1e-9));
        expect(m.sweeping, step['sweeping']);
      }
    });
  });
}
