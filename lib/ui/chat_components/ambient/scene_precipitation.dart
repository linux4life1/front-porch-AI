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

import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';

import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_render.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'ambient_stage_game.dart';

/// Rain or snow, drawn from the game's [SceneEffectsSim] by the recipe in
/// `scene_effects_render.dart`. Rain is a far sheet of the same drops
/// behind three depth bands of slanted streaks, with a splash where a near
/// drop meets the ground; snow is a far sheet of pinpoints, three bands of
/// round flakes and a halo on the nearest. Each pass is one batched draw
/// and the buffers are reused frame to frame, so a frame allocates nothing
/// per drop. Colours come from the scene's tokens.
class ScenePrecipitation extends Component
    with HasGameReference<AmbientStageGame> {
  ScenePrecipitation() : super(priority: 3);

  final Paint _paint = Paint();
  final List<Float32List> _bands = List.generate(4, (_) => Float32List(0));
  final List<int> _len = [0, 0, 0, 0];

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || sim.drops.isEmpty) return;
    final paints = game.tokens.paints;
    if (sim.spec.kind == SceneEffectKind.rain) {
      _rain(canvas, sim, paints.rain);
    } else if (sim.spec.kind == SceneEffectKind.snow) {
      _snow(canvas, sim, paints.snow);
    }
  }

  void _reserve(int perDrop, int drops) {
    final need = drops * perDrop;
    for (var b = 0; b < 4; b++) {
      if (_bands[b].length < need) _bands[b] = Float32List(need);
      _len[b] = 0;
    }
  }

  void _push(int b, double x, double y) {
    final list = _bands[b];
    list[_len[b]++] = x;
    list[_len[b]++] = y;
  }

  void _draw(Canvas canvas, int b, PointMode mode) {
    if (_len[b] == 0) return;
    canvas.drawRawPoints(
      mode,
      Float32List.sublistView(_bands[b], 0, _len[b]),
      _paint,
    );
  }

  void _rain(Canvas canvas, SceneEffectsSim sim, Color colour) {
    final w = sim.width;
    final h = sim.height;
    final wind = sim.spec.wind;
    // Bands 0..2 are the depth bands; band 3 is the far sheet, then the
    // splashes (the buffer is reused once the sheet is drawn).
    _reserve(4, sim.drops.length);
    for (final p in sim.drops) {
      final b = rainBand(p);
      final len = p.len * kSceneRainBandLength[b];
      _push(b, p.x, p.y);
      _push(b, p.x - len * wind, p.y - len);
      final fx = (p.x + w * kSceneFarSheetDx) % w;
      final fy = (p.y + h * kSceneFarSheetDy) % h;
      final flen = p.len * kSceneFarSheetLength;
      _push(3, fx, fy);
      _push(3, fx - flen * wind, fy - flen);
    }
    _paint.strokeCap = StrokeCap.butt;
    _paint
      ..color = colour.withValues(alpha: colour.a * kSceneFarSheetAlpha)
      ..strokeWidth = kSceneFarSheetWidth;
    _draw(canvas, 3, PointMode.lines);
    for (var b = 0; b < 3; b++) {
      _paint
        ..color = colour.withValues(alpha: colour.a * kSceneRainBandAlpha[b])
        ..strokeWidth = kSceneRainBandWidth[b];
      _draw(canvas, b, PointMode.lines);
    }
    _len[3] = 0;
    for (final p in sim.drops) {
      if (rainBand(p) != 2 || p.y < h - kSceneSplashZone) continue;
      final reach = 3 + p.len * 0.15;
      _push(3, p.x - reach, h - 1.5);
      _push(3, p.x + reach, h - 1.5);
    }
    _paint
      ..color = colour.withValues(alpha: colour.a * kSceneSplashAlpha)
      ..strokeWidth = 1;
    _draw(canvas, 3, PointMode.lines);
  }

  void _snow(Canvas canvas, SceneEffectsSim sim, Color colour) {
    final w = sim.width;
    final h = sim.height;
    _reserve(2, sim.drops.length);
    for (final p in sim.drops) {
      _push(SceneEffectsSim.snowBand(p), p.x, p.y);
      _push(
        3,
        (p.x + w * kSceneFarSheetDx) % w,
        (p.y + h * kSceneFarSheetDy) % h,
      );
    }
    _paint.strokeCap = StrokeCap.round;
    _paint
      ..color = colour.withValues(alpha: colour.a * kSceneSnowFarAlpha)
      ..strokeWidth = 1;
    _draw(canvas, 3, PointMode.points);
    // The nearest band's halo goes under its flakes.
    _paint
      ..color = colour.withValues(alpha: colour.a * kSceneSnowHaloAlpha)
      ..strokeWidth = kSceneSnowBandRadius[2] * 2 * kSceneSnowHaloWidth;
    _draw(canvas, 2, PointMode.points);
    for (var b = 0; b < 3; b++) {
      _paint
        ..color = colour.withValues(alpha: colour.a * kSceneSnowBandAlpha[b])
        ..strokeWidth = kSceneSnowBandRadius[b] * 2;
      _draw(canvas, b, PointMode.points);
    }
  }
}
