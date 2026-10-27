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
import 'package:flutter/material.dart' show Colors;

import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_render.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'ambient_stage_game.dart';

/// Rain or snow, drawn from the game's [SceneEffectsSim] by the recipe in
/// `scene_effects_render.dart`.
///
/// Rain is streak sprites with a soft tail, every drop (its far sheet and,
/// in heavy rain, a mid sheet too) in one `drawAtlas` call: each is placed
/// by its head, turned by the wind under the gust of the moment, scaled by
/// its length and tinted by the band and the flash, so a storm's strike
/// lights the whole sheet. Where a near drop lands a ring spreads and two
/// droplets jump ([SceneSplashes]). Snow is a far sheet of pinpoints,
/// three bands of round flakes and a halo on the nearest, each pass one
/// batched draw. Buffers are reused frame to frame; the streak atlas is
/// recorded once and freed with the layer. Colours come from the tokens.
class ScenePrecipitation extends Component
    with HasGameReference<AmbientStageGame> {
  ScenePrecipitation() : super(priority: 3);

  final Paint _paint = Paint();
  final List<Float32List> _bands = List.generate(4, (_) => Float32List(0));
  final List<int> _len = [0, 0, 0, 0];

  Image? _atlas;
  late final List<Rect> _atlasRects = _rects();
  List<RSTransform> _transforms = const [];
  List<Rect> _sprites = const [];
  List<Color> _tints = const [];
  int _quads = 0;
  final SceneSplashes _splashes = SceneSplashes();
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  /// How many streak quads the last frame drew, for tests.
  int get debugStreakCount => _quads;

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

  @override
  void onRemove() {
    _atlas?.dispose();
    _atlas = null;
    super.onRemove();
  }

  // Rain -------------------------------------------------------------

  static List<Rect> _rects() {
    var x = 0.0;
    final rects = <Rect>[];
    for (final w in kSceneStreakSpriteWidth) {
      rects.add(Rect.fromLTWH(x, 0, w, kSceneStreakSpriteHeight));
      x += w + 2;
    }
    return rects;
  }

  /// One column per band: a white streak fading from nothing at the tail
  /// to full at the head, with a soft edge. Modulated by each drop's tint.
  Image _buildAtlas() {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    for (final r in _atlasRects) {
      // Every drop's colour comes from the scene's tokens through the
      // modulate blend below; the atlas itself is only an alpha mask.
      paint.shader = Gradient.linear(
        r.topCenter,
        r.bottomCenter,
        // theme-keep: a white alpha mask, never a colour on screen
        const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0xFFFFFFFF)],
        const [0, 0.55, 1],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(r.width / 2)),
        paint,
      );
    }
    final last = _atlasRects.last;
    return recorder.endRecording().toImageSync(
      (last.right).ceil(),
      kSceneStreakSpriteHeight.toInt(),
    );
  }

  void _reserveQuads(int n) {
    if (_transforms.length >= n) return;
    _transforms = List.filled(n, RSTransform(1, 0, 0, 0));
    _sprites = List.filled(n, Rect.zero);
    _tints = List.filled(n, Colors.transparent);
  }

  void _quad(
    int i,
    double x,
    double y,
    double len,
    double lean,
    int band,
    Color tint,
  ) {
    final rect = _atlasRects[band];
    _transforms[i] = RSTransform.fromComponents(
      rotation: lean,
      scale: len / kSceneStreakSpriteHeight,
      anchorX: rect.width / 2,
      anchorY: rect.height,
      translateX: x,
      translateY: y,
    );
    _sprites[i] = rect;
    _tints[i] = tint;
  }

  void _rain(Canvas canvas, SceneEffectsSim sim, Color colour) {
    final w = sim.width;
    final h = sim.height;
    final atlas = _atlas ??= _buildAtlas();
    final gust = rainGust(sim.time);
    final lean = rainLean(sim.spec.wind, gust);
    final stretch = 0.85 + 0.15 * gust;
    final lit = rainLit(sim.flash);
    final heavy = sim.spec.density >= kSceneHeavyRainDensity;
    final sheets = heavy ? 3 : 2;
    _reserveQuads(sim.drops.length * sheets);
    Color tint(double share) {
      final a = colour.a * share * lit;
      return colour.withValues(alpha: a > 1 ? 1 : a);
    }

    var i = 0;
    for (final p in sim.drops) {
      final fx = (p.x + w * kSceneFarSheetDx) % w;
      final fy = (p.y + h * kSceneFarSheetDy) % h;
      _quad(
        i++,
        fx,
        fy,
        p.len * kSceneFarSheetLength * stretch,
        lean,
        0,
        tint(kSceneFarSheetAlpha),
      );
      if (heavy) {
        _quad(
          i++,
          (p.x + w * kSceneMidSheetDx) % w,
          (p.y + h * kSceneMidSheetDy) % h,
          p.len * kSceneMidSheetLength * stretch,
          lean,
          1,
          tint(kSceneMidSheetAlpha),
        );
      }
      final b = rainBand(p);
      _quad(
        i++,
        p.x,
        p.y,
        p.len * kSceneRainBandLength[b] * stretch,
        lean,
        b,
        tint(kSceneRainBandAlpha[b]),
      );
    }
    _quads = i;
    _paint
      ..shader = null
      // theme-keep: no tint of its own; the atlas call tints per drop.
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 1;
    canvas.drawAtlas(
      atlas,
      _transforms.sublist(0, i),
      _sprites.sublist(0, i),
      _tints.sublist(0, i),
      BlendMode.modulate,
      null,
      _paint,
    );
    _splashes.observe(sim.drops, sim.time, h);
    if (_splashes.live.isEmpty) return;
    _ring.color = colour;
    _paint.strokeCap = StrokeCap.round;
    for (final s in _splashes.live) {
      final p = SceneSplashes.progress(s, sim.time);
      final r = SceneSplashes.ringRadius(p);
      final a = colour.a * kSceneSplashRingAlpha * (1 - p) * lit;
      _ring.color = colour.withValues(alpha: a > 1 ? 1 : a);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s.x, h - 1),
          width: r * 2,
          height: r * 0.7,
        ),
        _ring,
      );
      final lift = SceneSplashes.dropletLift(p);
      if (lift <= 0) continue;
      _paint
        ..color = _ring.color
        ..strokeWidth = 1.6;
      canvas.drawPoints(PointMode.points, [
        Offset(s.x - 3 - 6 * p, h - 1 - lift),
        Offset(s.x + 3 + 6 * p, h - 1 - lift * 0.8),
      ], _paint);
    }
  }

  // Snow -------------------------------------------------------------

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
    _paint
      ..shader = null
      ..strokeCap = StrokeCap.round;
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
