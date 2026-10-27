// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The render recipe the stage and the web canvas share
// (scene_effects_render.dart, sceneEffectsRender.ts): the rain's depth
// bands, the flash's double strike, the ground fog's breath, and the bolt,
// which both surfaces must draw from the same seed and schedule number for
// number. The bolt vector below was produced by the web recipe.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_render.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'package:front_porch_ai/ui/theme/scene_palette.dart';

SceneDrop _drop(double a) => SceneDrop(0, 0, 500, 12, 0, a);

void main() {
  test('rain draws in three depth bands by the drop\'s own alpha', () {
    expect(rainBand(_drop(0.35)), 0);
    expect(rainBand(_drop(0.519)), 0);
    expect(rainBand(_drop(0.52)), 1);
    expect(rainBand(_drop(0.679)), 1);
    expect(rainBand(_drop(0.68)), 2);
    expect(rainBand(_drop(0.85)), 2);
    // Near is thickest, longest and brightest.
    expect(kSceneRainBandWidth[2], greaterThan(kSceneRainBandWidth[0]));
    expect(kSceneRainBandLength[2], greaterThan(kSceneRainBandLength[0]));
    expect(kSceneRainBandAlpha[2], greaterThan(kSceneRainBandAlpha[0]));
  });

  test('the flash strikes, goes dark, strikes again, then fades', () {
    expect([1.0, 0.8, 0.65, 0.5, 0.3, 0.1].map(flashShape), [
      1,
      1,
      0.15,
      0.85,
      0.42857142857142855,
      0.14285714285714285,
    ]);
    expect(flashShape(0), 0);
    expect(flashShape(-1), 0);
  });

  test('the bolt is the web\'s, point for point, and changes per flash', () {
    final bolt = sceneBolt(42, 5.25, 800, 600);
    final trunk = [
      for (final p in bolt.trunk)
        [
          double.parse(p.x.toStringAsFixed(6)),
          double.parse(p.y.toStringAsFixed(6)),
        ],
    ];
    final branch = [
      for (final p in bolt.branch)
        [
          double.parse(p.x.toStringAsFixed(6)),
          double.parse(p.y.toStringAsFixed(6)),
        ],
    ];
    expect(trunk, [
      [497.128779, -4],
      [473.207176, 26.016709],
      [453.541704, 53.757031],
      [463.235904, 101.213117],
      [466.208353, 136.280404],
      [466.268532, 178.425947],
      [488.195109, 209.236266],
      [495.113193, 238.655899],
      [478.161625, 270.981947],
      [482.522538, 312.643633],
    ]);
    expect(branch, [
      [463.235904, 101.213117],
      [487.188566, 128.380062],
      [507.448071, 153.882795],
      [520.100893, 182.413338],
      [533.783087, 210.828382],
    ]);
    expect(bolt.branch.first, bolt.trunk[3], reason: 'forks off the trunk');
    expect(bolt.trunk.last.y, lessThan(600 * 0.55 * 1.3));
    final next = sceneBolt(42, 17.5, 800, 600);
    expect(next.trunk, isNot(bolt.trunk), reason: 'a new strike, a new bolt');
    expect(sceneBolt(42, 5.25, 800, 600).trunk, bolt.trunk, reason: 'stable');
  });

  test('the ground fog is thickest at the ground and breathes', () {
    expect(groundFogStripeAlpha(0), lessThan(groundFogStripeAlpha(23)));
    expect(
      groundFogStripeAlpha(kSceneGroundFogStripes - 1),
      kSceneGroundFogAlpha,
    );
    expect(groundFogBreath(0), 0.8);
    for (var t = 0.0; t < 40; t += 0.7) {
      expect(groundFogBreath(t), inInclusiveRange(0.6, 1.0));
    }
  });

  test('nothing draws past the readability bounds the floor test assumes', () {
    // The floor test composites the thickest cloud at 0.75 of its paint and
    // the thickest fog at 0.5. A cloud's body and lifted top, both under
    // the sim's 0.75 ceiling on a cloud's own alpha, stay under 0.75 of
    // the paint together; the ground fog peaks under 0.5.
    const cloudCeiling = 0.75;
    for (final paints in [kSceneEffectPaintsDark, kSceneEffectPaintsLight]) {
      final p = paints.cloud.a;
      final body = p * cloudCeiling * kSceneCloudBodyAlpha;
      final top = p * cloudCeiling * kSceneCloudTopAlpha;
      expect(1 - (1 - body) * (1 - top), lessThanOrEqualTo(p * 0.75));
    }
    expect(kSceneGroundFogAlpha, lessThanOrEqualTo(0.5));
    expect(
      kSceneSnowHaloAlpha + kSceneSnowBandAlpha[2],
      lessThanOrEqualTo(1.1),
    );
  });

  test('the gust swells slowly and the flash lights the rain', () {
    for (var t = 0.0; t < 120; t += 0.3) {
      expect(rainGust(t), inInclusiveRange(0.65, 1.35));
    }
    expect(rainGust(0), 1 + 0.35 * 0 * math.sin(1));
    expect(rainLit(0), 1);
    expect(rainLit(1), closeTo(1.8, 1e-9));
    expect(rainLean(0, 1), 0);
    expect(rainLean(0.42, 1), lessThan(0), reason: 'leans with the wind');
    expect(rainLean(0.42, 1.35).abs(), greaterThan(rainLean(0.42, 1).abs()));
  });

  test('a near drop that respawns leaves a splash where it last was', () {
    final drops = [
      SceneDrop(100, 590, 500, 12, 0, 0.8), // near
      SceneDrop(200, 590, 500, 12, 0, 0.4), // far: never splashes
    ];
    final splashes = SceneSplashes();
    splashes.observe(drops, 0, 600);
    expect(splashes.live, isEmpty, reason: 'first look only remembers');
    drops[0].x = 104;
    drops[0].y = 598;
    drops[1].y = 598;
    splashes.observe(drops, 0.03, 600);
    expect(splashes.live, isEmpty, reason: 'still falling');
    drops[0].x = 300;
    drops[0].y = -12;
    drops[1].x = 310;
    drops[1].y = -12;
    splashes.observe(drops, 0.06, 600);
    expect(splashes.live, hasLength(1));
    expect(splashes.live.single.x, 104, reason: 'where it landed');
    expect(splashes.live.single.at, 0.06);
    expect(SceneSplashes.progress(splashes.live.single, 0.06), 0);
    expect(
      SceneSplashes.progress(splashes.live.single, 0.26),
      closeTo(0.5, 1e-9),
    );
    expect(SceneSplashes.ringRadius(0), 2);
    expect(SceneSplashes.ringRadius(1), 12);
    expect(SceneSplashes.dropletLift(0.4), closeTo(1.6, 1e-9));
    expect(SceneSplashes.dropletLift(0.8), lessThanOrEqualTo(0));
    splashes.observe(drops, 0.06 + kSceneSplashLife + 0.01, 600);
    expect(splashes.live, isEmpty, reason: 'gone after its life');
  });

  test('a scatter at the top of the stage is not a landing', () {
    final drops = [SceneDrop(50, 100, 500, 12, 0, 0.8)];
    final splashes = SceneSplashes();
    splashes.observe(drops, 0, 600);
    drops[0].y = 20;
    splashes.observe(drops, 0.1, 600);
    expect(splashes.live, isEmpty);
  });

  test('fog banks breathe on their own phase and stay under the fog bound', () {
    // The web twin (sceneEffectsRender.test.ts) pins the same numbers.
    expect(fogBankBreath(0, 0), 0.75);
    expect(fogBankBreath(3, 7.5), closeTo(0.817833, 1e-6));
    expect(fogBankBreath(1, 0), isNot(fogBankBreath(2, 0)));
    for (var t = 0.0; t < 60; t += 0.4) {
      for (var i = 0; i < kSceneFogBlobs; i++) {
        expect(fogBankBreath(i, t), inInclusiveRange(0.5, 1.0));
      }
    }
    // A bank is solid at its blob's alpha, which the sim keeps under 0.5,
    // times a breath of at most 1: under the floor test's fog bound.
    expect(kSceneFogBankCore, inExclusiveRange(0, 1));
    expect(kSceneFogBankSquash, inExclusiveRange(0, 1));
    expect(kSceneGroundFogAlpha, lessThanOrEqualTo(0.5));
  });
}
