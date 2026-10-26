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

import 'dart:ui';

import 'package:flame/components.dart';

import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'ambient_stage_game.dart';

/// Cloud shapes along the top of the stage. The stack is the web's, so
/// both surfaces composite the same colours and one readability test
/// covers both: tint (priority 0), clouds, fog, rain or snow, the flash.
/// Each cloud is one path of overlapping puffs, so a cloud is one draw
/// however many puffs it has.
class SceneCloudLayer extends Component
    with HasGameReference<AmbientStageGame> {
  SceneCloudLayer() : super(priority: 1);

  final Path _path = Path();
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || sim.clouds.isEmpty) return;
    final colour = game.tokens.paints.cloud;
    for (final c in sim.clouds) {
      _path.reset();
      for (final p in c.shapes) {
        _path.addOval(
          Rect.fromCenter(
            center: Offset(c.x + p.dx, p.y),
            width: p.rx * 2,
            height: p.ry * 2,
          ),
        );
      }
      _paint.color = colour.withValues(alpha: colour.a * c.a);
      canvas.drawPath(_path, _paint);
    }
  }
}

/// Fog: soft radial blobs drifting low across the stage, over the tint
/// and the clouds. Each blob's gradient is built once per scatter and moved
/// with a translate, so a frame makes no shaders.
class SceneFogLayer extends Component with HasGameReference<AmbientStageGame> {
  SceneFogLayer() : super(priority: 2);

  SceneEffectsSim? _builtFor;
  Color? _builtColour;
  List<Paint> _blobPaints = const [];

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || sim.fogBlobs.isEmpty) return;
    final colour = game.tokens.paints.fog;
    if (!identical(_builtFor, sim) || _builtColour != colour) {
      _builtFor = sim;
      _builtColour = colour;
      _blobPaints = [
        for (final b in sim.fogBlobs)
          Paint()
            ..shader = Gradient.radial(Offset.zero, b.r, [
              colour.withValues(alpha: colour.a * b.a),
              colour.withValues(alpha: 0),
            ]),
      ];
    }
    for (var i = 0; i < sim.fogBlobs.length; i++) {
      final b = sim.fogBlobs[i];
      canvas
        ..save()
        ..translate(b.x, b.y)
        ..drawCircle(Offset.zero, b.r, _blobPaints[i])
        ..restore();
    }
  }
}

/// The storm's lightning: a full-stage wash at the flash's strength, which
/// the sim fires on its seeded schedule and fades in a quarter second. The
/// game forwards each flash on `AmbientStageGame.flashes` for the scene
/// sound to time its thunder by.
class SceneLightningFlash extends Component
    with HasGameReference<AmbientStageGame> {
  SceneLightningFlash() : super(priority: 4);

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || sim.flash <= 0) return;
    final colour = game.tokens.paints.flash;
    _paint.color = colour.withValues(alpha: colour.a * sim.flash);
    canvas.drawRect(Rect.fromLTWH(0, 0, game.size.x, game.size.y), _paint);
  }
}
