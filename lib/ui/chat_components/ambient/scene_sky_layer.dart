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

import 'package:front_porch_ai/services/chat/scene/scene_sky.dart';
import 'package:front_porch_ai/ui/theme/scene_palette.dart';
import 'ambient_stage_game.dart';

/// The sky under the clouds: the minute-blended wash as a gradient down
/// from the top of the stage, the horizon band at dawn and dusk, and the
/// stars (`scene_sky.dart`, the web's `sceneSkyPlayer.ts`). The gradient
/// and the band change only with the minute and the stage, so they are
/// recorded once into a picture and replayed; through a sweep the picture
/// is re-recorded each frame, which lasts under two seconds. The stars
/// twinkle on the game's clock and hold still on a frozen stage.
class SceneSkyLayer extends Component with HasGameReference<AmbientStageGame> {
  SceneSkyLayer() : super(priority: 0);

  final Paint _paint = Paint();
  Picture? _picture;
  (double, double, double, bool, double)? _pictureKey;
  List<SceneStar>? _stars;

  @override
  void render(Canvas canvas) {
    final sky = game.tokens.sky;
    if (sky == null) return;
    final w = game.size.x;
    final h = game.size.y;
    final dark = game.tokens.dark;
    final minute = game.sky.shown;
    final key = (minute, w, h, dark, sky.veil);
    var picture = _picture;
    if (picture == null || key != _pictureKey) {
      _drop();
      picture = _record(Size(w, h), minute, dark, sky.veil);
      _picture = picture;
      _pictureKey = key;
    }
    canvas.drawPicture(picture);

    final visible = starVisibilityAt(minute) * sky.stars;
    if (visible <= 0) return;
    final stars = _stars ??= scatterStars(kSceneStarSeed, kSceneStarCount);
    final colour = dark ? kSceneStarDark : kSceneStarLight;
    final scale = dark ? 1.0 : kSceneStarLightScale;
    final frozen = game.effectsFrozen;
    final time = game.sky.time;
    for (final s in stars) {
      final twinkle = frozen ? 1.0 : starTwinkle(s, time);
      _paint.color = colour.withValues(
        alpha: s.alpha * visible * twinkle * scale,
      );
      canvas.drawCircle(Offset(s.x * w, s.y * h), s.size, _paint);
    }
  }

  Picture _record(Size size, double minute, bool dark, double veil) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    final scale = dark ? 1.0 : kSceneLightModeScale;
    final wash = skyWashAt(minute);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          Offset(0, size.height * kSceneSkyFade),
          [
            wash.color.withValues(
              alpha: wash.alpha * kSceneSkyTopAlpha * scale,
            ),
            wash.color.withValues(alpha: 0),
          ],
        ),
    );
    final glow = horizonGlowAt(minute);
    if (glow.strength > 0) {
      final colour = glow.dawn ? kSceneHorizonDawn : kSceneHorizonDusk;
      final alpha =
          glow.strength * kSceneHorizonAlpha * scale * (1 - 0.6 * veil);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.linear(
            Offset(0, size.height * 0.2),
            Offset(0, size.height * 0.6),
            [
              colour.withValues(alpha: 0),
              colour.withValues(alpha: alpha),
              colour.withValues(alpha: 0),
            ],
            const [0, 0.6, 1],
          ),
      );
    }
    return recorder.endRecording();
  }

  void _drop() {
    _picture?.dispose();
    _picture = null;
    _pictureKey = null;
  }

  @override
  void onRemove() {
    _drop();
    super.onRemove();
  }
}

/// The sun and the moon over the clouds, the fog and the rain, under the
/// flash: each
/// a soft glow and a disc on its arc, dimmed and spread wider the thicker
/// the weather, so a disc always reads through. The moon's dark side is
/// cut from its face, so what shows behind it is the sky. Recorded like
/// the sky, by the minute and the phase.
class SceneDiscLayer extends Component with HasGameReference<AmbientStageGame> {
  SceneDiscLayer() : super(priority: 4);

  Picture? _picture;
  (double, double, double, bool, double, double)? _pictureKey;

  @override
  void render(Canvas canvas) {
    final sky = game.tokens.sky;
    if (sky == null) return;
    final w = game.size.x;
    final h = game.size.y;
    final dark = game.tokens.dark;
    final minute = game.sky.shown;
    final key = (minute, w, h, dark, sky.veil, sky.moonPhase);
    var picture = _picture;
    if (picture == null || key != _pictureKey) {
      _drop();
      picture = _record(Size(w, h), minute, dark, sky);
      _picture = picture;
      _pictureKey = key;
    }
    canvas.drawPicture(picture);
  }

  Picture _record(Size size, double minute, bool dark, SceneSky sky) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final veil = sky.veil;
    final unit = w < h ? w : h;

    final sun = skyArcAt(minute, rise: kSceneSunrise, set: kSceneSunset);
    if (sun != null) {
      final centre = Offset(sun.x * w, sun.y * h);
      final r = unit * 0.028 < 10 ? 10.0 : unit * 0.028;
      final a = _horizonFade(sun.alt) * (dark ? 1.0 : kSceneSunLightScale);
      final warm = sun.alt < 0.35 ? kSceneSunLow : kSceneSunHigh;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.radial(
            centre,
            r * (6 + 6 * veil),
            [
              warm.withValues(alpha: (0.45 + 0.25 * veil) * a),
              warm.withValues(alpha: (0.12 + 0.1 * veil) * a),
              warm.withValues(alpha: 0),
            ],
            const [0, 0.35, 1],
          ),
      );
      canvas.drawCircle(
        centre,
        r * (1 + 0.3 * veil),
        Paint()..color = warm.withValues(alpha: (0.95 - 0.45 * veil) * a),
      );
    }

    final moon = skyArcAt(minute, rise: kSceneMoonrise, set: kSceneMoonset);
    if (moon != null) {
      final centre = Offset(moon.x * w, moon.y * h);
      final r = unit * 0.022 < 8 ? 8.0 : unit * 0.022;
      final a = _horizonFade(moon.alt) * (dark ? 1.0 : kSceneMoonLightScale);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.radial(centre, r * (5 + 6 * veil), [
            kSceneMoonGlow.withValues(alpha: (0.25 + 0.3 * veil) * a),
            kSceneMoonGlow.withValues(alpha: 0),
          ]),
      );
      // The lit face: the disc less a second disc slid across it, centred
      // on the moon at new and two radii off at full; waxing lights the
      // right edge. Even-odd of the two circles, clipped to the disc.
      final lit = 1 - (sky.moonPhase - 0.5).abs() * 2;
      final off = (sky.moonPhase < 0.5 ? -1 : 1) * lit * r * 2.05;
      final face = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: centre, radius: r))
        ..addOval(Rect.fromCircle(center: centre.translate(off, 0), radius: r));
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: centre, radius: r)),
      );
      canvas.drawPath(
        face,
        Paint()..color = kSceneMoon.withValues(alpha: (0.95 - 0.4 * veil) * a),
      );
      canvas.restore();
    }
    return recorder.endRecording();
  }

  /// A disc fades in over the first third of its climb from the horizon.
  static double _horizonFade(double alt) {
    final v = alt * 3;
    return v < 0 ? 0 : (v > 1 ? 1 : v);
  }

  void _drop() {
    _picture?.dispose();
    _picture = null;
    _pictureKey = null;
  }

  @override
  void onRemove() {
    _drop();
    super.onRemove();
  }
}
