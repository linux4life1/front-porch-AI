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

// The Ambient Stage's moving weather (docs/design/ambient-stage.md, PR 2):
// the seeded generator, the budgets, the scatter and the motion match the
// shared vectors the web sim is pinned to as well
// (test/fixtures/ambient/scene_effects_vectors.json, generated from the
// design prototype's own code), so one seed draws the same sky on both
// surfaces. Plus the High Contrast cap in the gate and what travels on the
// wire.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'package:front_porch_ai/services/chat/scene/scene_gate.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/chat/weather_segments.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

final Map<String, dynamic> _vectors =
    jsonDecode(
          File(
            'test/fixtures/ambient/scene_effects_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> get _cases =>
    (_vectors['cases'] as List).cast<Map<String, dynamic>>();

List<double> _nums(Object? list) =>
    (list as List).map((n) => (n as num).toDouble()).toList();

SceneEffectsSim _simFor(Map<String, dynamic> c) => SceneEffectsSim(
  spec: SceneEffectSpec.forCondition(c['condition'] as String),
  seed: c['seed'] as int,
  width: (c['width'] as num).toDouble(),
  height: (c['height'] as num).toDouble(),
);

void main() {
  test('mulberry32 and the seed hash match the prototype bit for bit', () {
    final mul = (_vectors['mulberry32'] as Map).cast<String, Object?>();
    expect(mul, isNotEmpty);
    for (final e in mul.entries) {
      final rnd = Mulberry32(int.parse(e.key));
      final got = [for (var i = 0; i < 5; i++) rnd.next()];
      expect(got, _nums(e.value), reason: 'seed ${e.key}');
    }
    final fnv = (_vectors['fnv1a32'] as Map).cast<String, Object?>();
    for (final e in fnv.entries) {
      expect(fnv1a32(e.key), e.value, reason: '"${e.key}"');
    }
    expect(
      sceneSeed(
        sessionSeed: 'porch-chat',
        dayCount: 12,
        daypart: 'evening',
        condition: 'rain',
      ),
      fnv['porch-chat|day-12|evening|rain'],
    );
  });

  test('every condition carries the budgets the web is pinned to', () {
    final specs = (_vectors['specs'] as Map).cast<String, Object?>();
    expect(
      specs.keys.toSet(),
      WeatherCondition.values.map((c) => c.name).toSet(),
    );
    for (final e in specs.entries) {
      expect(
        SceneEffectSpec.forCondition(e.key).toWire(),
        e.value,
        reason: e.key,
      );
    }
    expect(_vectors['particleCap'], kSceneParticleCap);
    expect(_vectors['fogBlobs'], kSceneFogBlobs);
    expect(
      SceneEffectSpec.forCondition('acid_drizzle'),
      SceneEffectSpec.none,
      reason: 'a condition this build does not know paints nothing',
    );
  });

  test('the particle budget scales with the stage and caps at 400', () {
    final rain = SceneEffectSpec.forCondition('rain');
    final storm = SceneEffectSpec.forCondition('storm');
    final snow = SceneEffectSpec.forCondition('snow');
    expect(rain.particlesFor(800, 600), 168);
    expect(rain.particlesFor(1600, 600), 336, reason: 'double the area');
    expect(rain.particlesFor(400, 300), 42, reason: 'a quarter of it');
    expect(snow.particlesFor(800, 600), 106);
    expect(storm.particlesFor(800, 600), 312);
    expect(
      storm.particlesFor(800, 600),
      greaterThan(rain.particlesFor(800, 600)),
    );
    for (final s in [rain, storm, snow]) {
      expect(s.particlesFor(3840, 2160), kSceneParticleCap);
      expect(s.particlesFor(0, 0), 0);
    }
    expect(SceneEffectSpec.forCondition('cloudy').particlesFor(3840, 2160), 0);
  });

  test('a seed scatters exactly the prototype\'s first frame', () {
    for (final c in _cases) {
      final sim = _simFor(c);
      final name = c['condition'];
      expect(sim.seed, fnv1a32(c['seedInput'] as String));
      expect(sim.drops.length, c['count'], reason: '$name count');
      final initial = c['initial'] as Map<String, dynamic>;
      final drops = (initial['drops'] as List).map(_nums).toList();
      for (var i = 0; i < drops.length; i++) {
        final d = sim.drops[i];
        expect([d.x, d.y, d.v, d.len, d.drift, d.a], drops[i]);
      }
      final clouds = (initial['clouds'] as List).map(_nums).toList();
      expect(sim.clouds.length, (c['spec'] as Map)['clouds']);
      for (var i = 0; i < clouds.length; i++) {
        final k = sim.clouds[i];
        expect([k.x, k.y, k.w, k.h, k.v, k.a, k.puffs, k.seed], clouds[i]);
      }
      final fog = (initial['fogBlobs'] as List).map(_nums).toList();
      expect(sim.fogBlobs.length, (c['spec'] as Map)['fog'] == true ? 7 : 0);
      for (var i = 0; i < fog.length; i++) {
        final f = sim.fogBlobs[i];
        expect([f.x, f.y, f.r, f.v, f.a], fog[i]);
      }
      expect(sim.nextFlashAt, initial['nextFlashAt']);
    }
  });

  test('stepping moves the weather exactly as the web steps it', () {
    for (final c in _cases) {
      final sim = _simFor(c);
      final flashes = <List<double>>[];
      sim.onFlash = (f) => flashes.add([f.at, f.rumbleDelay]);
      final after = c['after'] as Map<String, dynamic>;
      final dt = (after['dt'] as num).toDouble();
      for (var i = 0; i < (after['steps'] as int); i++) {
        sim.advance(dt);
      }
      final name = c['condition'];
      final drops = (after['drops'] as List).map(_nums).toList();
      for (var i = 0; i < drops.length; i++) {
        final got = [sim.drops[i].x, sim.drops[i].y];
        if (name == 'snow') {
          // Sway goes through sin(), which two maths libraries may round a
          // last bit apart; everything else is exact.
          expect(got[0], closeTo(drops[i][0], 1e-6));
          expect(got[1], closeTo(drops[i][1], 1e-6));
        } else {
          expect(got, drops[i], reason: '$name drop $i');
        }
      }
      expect([for (final k in sim.clouds.take(2)) k.x], _nums(after['clouds']));
      expect([
        for (final f in sim.fogBlobs.take(2)) f.x,
      ], _nums(after['fogBlobs']));
      expect(flashes, (after['flashes'] as List).map(_nums).toList());
      expect(sim.flash, after['flash']);
    }
  });

  test('the same seed and steps give the same sky; another seed does not', () {
    final spec = SceneEffectSpec.forCondition('storm');
    SceneEffectsSim run(int seed) {
      final sim = SceneEffectsSim(
        spec: spec,
        seed: seed,
        width: 900,
        height: 700,
      );
      for (var i = 0; i < 200; i++) {
        sim.advance(i.isEven ? 1 / 60 : 1 / 24);
      }
      return sim;
    }

    List<double> sky(SceneEffectsSim s) => [
      for (final d in s.drops) ...[d.x, d.y],
      for (final c in s.clouds) c.x,
      s.flash,
      s.nextFlashAt,
    ];
    expect(sky(run(7)), sky(run(7)));
    expect(sky(run(7)), isNot(sky(run(8))));
  });

  test('the storm flashes on its seeded schedule and fades fast', () {
    final sim = SceneEffectsSim(
      spec: SceneEffectSpec.forCondition('storm'),
      seed: 1234,
      width: 800,
      height: 600,
    );
    final fired = <SceneFlash>[];
    sim.onFlash = fired.add;
    final first = sim.nextFlashAt;
    expect(first, inInclusiveRange(2.5, 8.5));
    while (sim.time < first) {
      sim.advance(1 / 30);
    }
    expect(fired, hasLength(1));
    expect(fired.single.rumbleDelay, inInclusiveRange(0.4, 1.8));
    expect(sim.flash, greaterThan(0.8));
    expect(sim.nextFlashAt - sim.time, inInclusiveRange(7 - 1e-9, 19));
    for (var i = 0; i < 9; i++) {
      sim.advance(1 / 30);
    }
    expect(sim.flash, 0, reason: 'gone within a third of a second');
    final rain = SceneEffectsSim(
      spec: SceneEffectSpec.forCondition('rain'),
      seed: 1234,
      width: 800,
      height: 600,
    )..onFlash = fired.add;
    for (var i = 0; i < 900; i++) {
      rain.advance(1 / 30);
    }
    expect(fired, hasLength(1), reason: 'plain rain never flashes');
  });

  test('High Contrast holds Tint and effects to Tint only', () {
    for (final theme in AppThemeId.values) {
      expect(sceneLevelFor(AmbientScene.off, theme), isNull);
      expect(sceneLevelFor(AmbientScene.tint, theme), SceneLevel.tint);
      expect(
        sceneLevelFor(AmbientScene.effects, theme),
        theme == AppThemeId.highContrast ? SceneLevel.tint : SceneLevel.effects,
        reason: theme.label,
      );
    }
  });

  test('the gate holds High Contrast to Tint only and seeds from the chat', () {
    const day = DailyWeather(
      condition: WeatherCondition.rain,
      temp: TempBand.cold,
      season: 'autumn',
    );
    const segment = SegmentWeather(
      day: day,
      segment: DaySegment.night,
      condition: WeatherCondition.storm,
      tempC: 3,
    );
    SceneTokens? at(AmbientScene scene, AppThemeId theme) => SceneGate.resolve(
      scene: scene,
      theme: theme,
      day: day,
      segment: segment,
      daypart: 'night',
      dark: true,
      sessionSeed: 'chat-1',
      dayCount: 12,
      pauseWhileGenerating: false,
    );
    for (final theme in AppThemeId.values) {
      final hc = theme == AppThemeId.highContrast;
      final effects = at(AmbientScene.effects, theme)!;
      expect(
        effects.level,
        hc ? SceneLevel.tint : SceneLevel.effects,
        reason: theme.label,
      );
      expect(effects.hasEffects, !hc, reason: theme.label);
      expect(at(AmbientScene.tint, theme)!.level, SceneLevel.tint);
      expect(at(AmbientScene.off, theme), isNull);
    }
    final s = at(AmbientScene.effects, AppThemeId.values.first)!;
    expect(
      s.seed,
      sceneSeed(
        sessionSeed: 'chat-1',
        dayCount: 12,
        daypart: 'night',
        condition: 'storm',
      ),
    );
    expect(s.effects, SceneEffectSpec.forCondition('storm'));
    expect(s.pauseWhileGenerating, isFalse);
  });

  test('what moves travels top-level, its paints in each mode', () {
    SceneTokens at(bool dark, {SceneLevel level = SceneLevel.effects}) =>
        SceneSim.resolve(
          daypart: 'night',
          condition: WeatherCondition.storm,
          temp: TempBand.cold,
          dark: dark,
          level: level,
          seed: 3682408742,
          pauseWhileGenerating: false,
        );
    final s = at(true);
    expect(s.hasEffects, isTrue);
    final w = SceneTokens.wireOf(dark: s, light: at(false));
    expect(w['level'], 'effects');
    expect(w['seed'], 3682408742);
    expect(w['pauseWhileGenerating'], false);
    final e = (w['effects'] as Map).cast<String, Object?>();
    expect(e, {
      'kind': 'rain',
      'density': 0.00065,
      'clouds': 9,
      'fog': false,
      'lightning': true,
      'wind': 0.42,
    });
    final css = RegExp(r'^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$');
    Map<String, Object?> paintsOf(String mode) =>
        ((w[mode] as Map)['paints'] as Map).cast<String, Object?>();
    for (final mode in ['dark', 'light']) {
      final paints = paintsOf(mode);
      expect(paints.keys.toSet(), {
        'rain',
        'snow',
        'cloud',
        'fog',
        'fogClear',
        'flash',
      });
      for (final p in paints.values) {
        expect(p, matches(css));
      }
    }
    expect(paintsOf('dark'), isNot(paintsOf('light')));
    expect(paintsOf('dark')['rain'], WebThemeTokens.css(s.paints.rain));
    // jsonEncode is what the web socket does with it.
    expect(() => jsonEncode(w), returnsNormally);

    final tint = at(true, level: SceneLevel.tint);
    expect(
      SceneTokens.wireOf(
        dark: tint,
        light: at(false, level: SceneLevel.tint),
      )['level'],
      'tint',
    );
    expect(tint.hasEffects, isFalse);
    expect(tint, isNot(s), reason: 'level is part of the value');
  });

  test('clouds and fog at their thickest leave canvas text readable', () {
    // The moving weather paints behind the bubbles like the tint, so the
    // chat's own canvas text must stay at least large-text legible (3:1)
    // under the thickest cloud (0.75 of its paint) or fog blob (0.5) over
    // every wash. High Contrast never gets effects.
    const dayparts = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    for (final theme in AppThemeId.values) {
      if (theme == AppThemeId.highContrast) continue;
      for (final dark in [true, false]) {
        final p = dark ? theme.palettes.dark : theme.palettes.light;
        for (final d in dayparts) {
          for (final c in WeatherCondition.values) {
            final s = SceneSim.resolve(
              daypart: d,
              condition: c,
              temp: TempBand.mild,
              dark: dark,
            );
            final ground = s.compositeOver(p.background);
            final peaks = [
              if (s.effects.clouds > 0)
                s.paints.cloud.withValues(alpha: s.paints.cloud.a * 0.75),
              if (s.effects.fog)
                s.paints.fog.withValues(alpha: s.paints.fog.a * 0.5),
            ];
            for (final peak in peaks) {
              final ratio = contrastRatio(
                p.textPrimary,
                Color.alphaBlend(peak, ground),
              );
              expect(
                ratio,
                greaterThanOrEqualTo(3),
                reason:
                    '${theme.label} ${dark ? 'dark' : 'light'} $d/${c.name}: '
                    '${ratio.toStringAsFixed(2)}',
              );
            }
          }
        }
      }
    }
  });
}
