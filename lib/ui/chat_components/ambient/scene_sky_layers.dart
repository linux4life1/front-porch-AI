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
import 'package:front_porch_ai/services/chat/scene/scene_fog_mist.dart';
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

/// Fog: two layers of mist streaming right across the stage over the tint
/// and the clouds, far and slow behind near and faster, each thickest
/// toward the ground and breathing on its own phase
/// (`scene_fog_mist.dart`). Each layer's texture is built once per
/// scatter and colour, painted in the fog colour, and its share and
/// breath ride on the paint's alpha; a frame only draws the two textures
/// twice each, so it makes no images and no shaders.
class SceneFogLayer extends Component with HasGameReference<AmbientStageGame> {
  SceneFogLayer() : super(priority: 2);

  SceneEffectsSim? _builtFor;
  Color? _builtColour;
  List<Image> _mist = const [];
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  /// How many mist textures are held now, for tests.
  @visibleForTesting
  int get debugMistCount => _mist.length;

  @override
  void render(Canvas canvas) {
    final sim = game.effects;
    if (sim == null || !sim.spec.fog) return;
    final colour = game.tokens.paints.fog;
    if (!identical(_builtFor, sim) || _builtColour != colour) {
      _dropMist();
      _builtFor = sim;
      _builtColour = colour;
      _mist = [
        for (var l = 0; l < kSceneMistLayers; l++)
          _mistImage(sceneMist(sim.seed, l), colour),
      ];
    }
    final w = game.size.x;
    final h = game.size.y;
    final tileW = w * kSceneMistSpan;
    final src = Rect.fromLTWH(
      0,
      0,
      kSceneMistWidth.toDouble(),
      kSceneMistHeight.toDouble(),
    );
    for (var l = 0; l < _mist.length; l++) {
      _paint.color = _paint.color.withValues(
        alpha: kSceneMistShare[l] * mistBreath(l, sim.time),
      );
      final shift = mistShift(l, sim.time, w);
      canvas
        ..drawImageRect(
          _mist[l],
          src,
          Rect.fromLTWH(shift - tileW, 0, tileW, h),
          _paint,
        )
        ..drawImageRect(
          _mist[l],
          src,
          Rect.fromLTWH(shift, 0, tileW, h),
          _paint,
        );
    }
  }

  @override
  void onRemove() {
    _dropMist();
    super.onRemove();
  }

  /// The density as a texture in the fog [colour], its alpha scaled by
  /// the density, one pixel per value.
  static Image _mistImage(List<double> density, Color colour) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final pixel = Paint();
    for (var y = 0; y < kSceneMistHeight; y++) {
      for (var x = 0; x < kSceneMistWidth; x++) {
        final a = density[y * kSceneMistWidth + x];
        if (a <= 0) continue;
        pixel.color = colour.withValues(alpha: colour.a * a);
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), pixel);
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(kSceneMistWidth, kSceneMistHeight);
    picture.dispose();
    return image;
  }

  void _dropMist() {
    for (final m in _mist) {
      m.dispose();
    }
    _mist = const [];
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
