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
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'ambient_stage_game.dart';

/// Rain or snow, drawn from the game's [SceneEffectsSim]. Rain is one batch
/// of slanted line segments; snow is three batches of round points, one per
/// size band. The buffers are reused frame to frame, so a frame allocates
/// nothing per drop. Colours come from the scene's tokens.
class ScenePrecipitation extends Component
    with HasGameReference<AmbientStageGame> {
  ScenePrecipitation() : super(priority: 3);

  final Paint _paint = Paint();
  Float32List _lines = Float32List(0);
  final List<Float32List> _bands = List.generate(3, (_) => Float32List(0));
  final List<int> _bandLength = [0, 0, 0];

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

  void _rain(Canvas canvas, SceneEffectsSim sim, Color colour) {
    final need = sim.drops.length * 4;
    if (_lines.length < need) _lines = Float32List(need);
    final wind = sim.spec.wind;
    var i = 0;
    for (final p in sim.drops) {
      _lines[i++] = p.x;
      _lines[i++] = p.y;
      _lines[i++] = p.x - p.len * wind;
      _lines[i++] = p.y - p.len;
    }
    _paint
      ..color = colour
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.butt;
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(_lines, 0, i),
      _paint,
    );
  }

  void _snow(Canvas canvas, SceneEffectsSim sim, Color colour) {
    final need = sim.drops.length * 2;
    for (var b = 0; b < 3; b++) {
      if (_bands[b].length < need) _bands[b] = Float32List(need);
      _bandLength[b] = 0;
    }
    for (final p in sim.drops) {
      final b = SceneEffectsSim.snowBand(p);
      final list = _bands[b];
      list[_bandLength[b]++] = p.x;
      list[_bandLength[b]++] = p.y;
    }
    _paint.strokeCap = StrokeCap.round;
    for (var b = 0; b < 3; b++) {
      if (_bandLength[b] == 0) continue;
      _paint
        ..color = colour.withValues(alpha: colour.a * kSceneSnowBandAlpha[b])
        ..strokeWidth = kSceneSnowBandRadius[b] * 2;
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(_bands[b], 0, _bandLength[b]),
        _paint,
      );
    }
  }
}
