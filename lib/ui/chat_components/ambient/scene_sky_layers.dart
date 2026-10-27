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

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:front_porch_ai/services/chat/scene/scene_effects_render.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'ambient_stage_game.dart';

/// Cloud shapes along the top of the stage. The stack is the web's, so
/// both surfaces composite the same colours and one readability test
/// covers both: tint (priority 0), clouds, fog, rain or snow, the flash.
/// Each cloud is a body and a smaller, lifted highlight over it, two
/// paths of overlapping puffs, so the top reads lit and the belly heavy
/// (`scene_effects_render.dart`); it bobs slowly on the sim's clock.
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
    final h = game.size.y;
    for (final c in sim.clouds) {
      final bob = cloudBob(c.seed, sim.time) * h;
      _path.reset();
      for (final p in c.shapes) {
        _path.addOval(
          Rect.fromCenter(
            center: Offset(c.x + p.dx, p.y + bob),
            width: p.rx * 2,
            height: p.ry * 2,
          ),
        );
      }
      _paint.color = colour.withValues(
        alpha: colour.a * c.a * kSceneCloudBodyAlpha,
      );
      canvas.drawPath(_path, _paint);
      _path.reset();
      for (final p in c.shapes) {
        _path.addOval(
          Rect.fromCenter(
            center: Offset(c.x + p.dx, p.y + bob - p.ry * kSceneCloudTopLift),
            width: p.rx * 2 * kSceneCloudTopScale,
            height: p.ry * 2 * kSceneCloudTopScale,
          ),
        );
      }
      _paint.color = colour.withValues(
        alpha: colour.a * c.a * kSceneCloudTopAlpha,
      );
      canvas.drawPath(_path, _paint);
    }
  }
}

/// Fog: soft radial blobs rolling low across the stage, over the tint
/// and the clouds, and a band of ground fog thickest at the bottom edge
/// that breathes on the sim's clock. Each blob's gradient is built once
/// per scatter and moved with a translate; the ground band is plain
/// rectangles, so a frame makes no shaders.
class SceneFogLayer extends Component with HasGameReference<AmbientStageGame> {
  SceneFogLayer() : super(priority: 2);

  SceneEffectsSim? _builtFor;
  Color? _builtColour;
  List<Paint> _blobPaints = const [];
  List<Shader> _shaders = const [];
  final Paint _ground = Paint();

  /// How many blob gradients are held now, for tests.
  @visibleForTesting
  int get debugShaderCount => _shaders.length;

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || sim.fogBlobs.isEmpty) return;
    final colour = game.tokens.paints.fog;
    if (!identical(_builtFor, sim) || _builtColour != colour) {
      _dropShaders();
      _builtFor = sim;
      _builtColour = colour;
      _shaders = [
        for (final b in sim.fogBlobs)
          Gradient.radial(Offset.zero, b.r, [
            colour.withValues(alpha: colour.a * b.a),
            colour.withValues(alpha: 0),
          ]),
      ];
      _blobPaints = [for (final s in _shaders) Paint()..shader = s];
    }
    final h = game.size.y;
    for (var i = 0; i < sim.fogBlobs.length; i++) {
      final b = sim.fogBlobs[i];
      canvas
        ..save()
        ..translate(b.x, b.y + fogBob(i, sim.time) * h)
        ..drawCircle(Offset.zero, b.r, _blobPaints[i])
        ..restore();
    }
    final w = game.size.x;
    final breath = groundFogBreath(sim.time);
    final band = h * kSceneGroundFogHeight;
    final stripe = band / kSceneGroundFogStripes;
    for (var i = 0; i < kSceneGroundFogStripes; i++) {
      _ground.color = colour.withValues(
        alpha: colour.a * groundFogStripeAlpha(i) * breath,
      );
      final top = h - band + i * stripe;
      canvas.drawRect(Rect.fromLTWH(0, top, w, stripe + 0.5), _ground);
    }
  }

  @override
  void onRemove() {
    _dropShaders();
    super.onRemove();
  }

  void _dropShaders() {
    for (final s in _shaders) {
      s.dispose();
    }
    _shaders = const [];
    _blobPaints = const [];
    _builtFor = null;
    _builtColour = null;
  }
}

/// The storm's lightning: a strike, a dark beat and a second strike
/// ([flashShape]) over the quarter second the sim's flash lasts, as a
/// full-stage wash with a forked bolt down from the top, seeded from the
/// scene and the flash's place in the schedule so both surfaces draw the
/// same bolt. The game forwards each flash on `AmbientStageGame.flashes`
/// for the scene sound to time its thunder by.
class SceneLightningFlash extends Component
    with HasGameReference<AmbientStageGame> {
  SceneLightningFlash() : super(priority: 4);

  final Paint _paint = Paint();
  final Paint _bolt = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Path _path = Path();
  double _boltFor = double.nan;
  ({List<math.Point<double>> trunk, List<math.Point<double>> branch})? _shape;

  /// The schedule time the bolt on the stage was drawn for, for tests;
  /// NaN before any flash has rendered.
  @visibleForTesting
  double get debugBoltAt => _boltFor;

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || sim.flash <= 0) return;
    final strength = flashShape(sim.flash);
    final colour = game.tokens.paints.flash;
    final w = game.size.x;
    final h = game.size.y;
    _paint.color = colour.withValues(alpha: colour.a * strength);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _paint);
    // The bolt is worked out once per flash: the schedule moves on when
    // the flash fires and holds for its life.
    if (_boltFor != sim.nextFlashAt) {
      _boltFor = sim.nextFlashAt;
      _shape = sceneBolt(sim.seed, sim.nextFlashAt, w, h);
      _path.reset();
      _trace(_shape!.trunk);
      _trace(_shape!.branch);
    }
    _bolt
      ..strokeWidth = kSceneBoltGlowWidth
      ..color = colour.withValues(alpha: kSceneBoltGlowAlpha * strength);
    canvas.drawPath(_path, _bolt);
    _bolt
      ..strokeWidth = kSceneBoltCoreWidth
      ..color = colour.withValues(alpha: kSceneBoltCoreAlpha * strength);
    canvas.drawPath(_path, _bolt);
  }

  void _trace(List<math.Point<double>> points) {
    _path.moveTo(points.first.x, points.first.y);
    for (final p in points.skip(1)) {
      _path.lineTo(p.x, p.y);
    }
  }
}
