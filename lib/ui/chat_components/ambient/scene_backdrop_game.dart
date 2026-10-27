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
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Colors;

import 'package:front_porch_ai/services/chat/scene/scene_backdrop_transition.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';

/// The colours the move paints with: the [veil] every picture wears, the
/// [light] of the sweep and the strike, the [fog] of the roll.
typedef SceneMovePaints = ({ui.Color veil, ui.Color light, ui.Color fog});

/// A frame at rest: the current picture alone under the veil.
const SceneMoveFrame _rest = (
  outAlpha: 0,
  outScale: 1,
  outDx: 0,
  inAlpha: 1,
  inScale: 1,
  inDx: 0,
  sweep: -1,
  sweepAlpha: 0,
  cover: 0,
  flash: 0,
  dip: 0,
  title: 0,
);

/// The place's picture behind the chat as a Flame game under the Ambient
/// Stage, and the move from one place to the next
/// (`scene_backdrop_transition.dart`): the old picture drifts off under a
/// sweep of light while the new one settles, or fog rolls over and clears
/// on the new place, or a strike cuts there, by the weather's call. It
/// ticks only while a move runs and pauses itself on the last frame, so
/// a still picture costs no frames at all (the rule every stage keeps).
/// Pictures are owned by the layer that hands them in; the game draws.
class SceneBackdropGame extends FlameGame {
  SceneBackdropGame({required this.paints}) {
    pauseWhenBackgrounded = false;
    // Still until a move starts; the first picture paints through
    // repaintOnce and onAttach without the ticker.
    pauseEngine();
  }

  SceneMovePaints paints;

  /// Told when a move starts (true) and when it has ended (false).
  void Function(bool moving)? onMoving;

  ui.Image? _current;
  ui.Image? _previous;
  SceneMoveKind _kind = SceneMoveKind.travel;
  double _t = 0;
  double _duration = 0;
  List<SceneFogBank> _banks = const [];
  bool _pauseAfterRender = false;
  final ui.Paint _picture = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final ui.Paint _wash = ui.Paint();
  final ui.Paint _sweep = ui.Paint()..blendMode = ui.BlendMode.plus;

  /// Whether a move is running now.
  bool get moving => _duration > 0;

  /// The move under way, or the last one.
  SceneMoveKind get kind => _kind;

  /// How far the move has run, 0 to 1.
  double get progress => moving ? _t / _duration : 1;

  /// The picture on the stage now, for tests.
  @visibleForTesting
  ui.Image? get debugCurrent => _current;

  /// The picture on its way out, for tests; null once the move is over.
  @visibleForTesting
  ui.Image? get debugPrevious => _previous;

  /// Shows [image]: at once when it is the first picture or [instant]
  /// (reduce motion), else as the [kind] move from the picture on the
  /// stage. [seed] fixes the fog banks per place.
  void show(
    ui.Image image, {
    required SceneMoveKind kind,
    required int seed,
    bool instant = false,
  }) {
    if (identical(image, _current)) return;
    if (_current == null || instant) {
      _current = image;
      _previous = null;
      _finish();
      if (!paused) pauseEngine();
      repaintOnce();
      return;
    }
    _previous = _current;
    _current = image;
    _kind = kind;
    _t = 0;
    _duration = sceneMoveDuration(kind);
    _banks = kind == SceneMoveKind.fogRoll
        ? sceneFogBanks(Mulberry32(seed).next)
        : const [];
    onMoving?.call(true);
    if (paused) resumeEngine();
  }

  void _finish() {
    if (_duration > 0) {
      _duration = 0;
      _previous = null;
      onMoving?.call(false);
    }
  }

  /// Paints once while paused, without starting the ticker. Before the
  /// render box attaches there is no loop to step; [onAttach] paints then.
  void repaintOnce() {
    if (paused && isAttached) stepEngine(stepTime: 0);
  }

  @override
  void onAttach() {
    super.onAttach();
    update(0);
  }

  @override
  ui.Color backgroundColor() => Colors.transparent;

  @override
  void update(double dt) {
    super.update(dt);
    if (!moving) return;
    _t += dt;
    if (_t >= _duration) {
      _finish();
      // One last frame at rest, then the ticker stops.
      _pauseAfterRender = true;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    final w = size.x;
    final h = size.y;
    if (w <= 0 || h <= 0) return;
    final f = moving ? sceneMoveFrame(_kind, progress) : _rest;
    final all = ui.Rect.fromLTWH(0, 0, w, h);
    final previous = _previous;
    if (previous != null && f.outAlpha > 0) {
      _drawPicture(canvas, previous, f.outAlpha, f.outScale, f.outDx, w, h);
    }
    final current = _current;
    if (current != null && f.inAlpha > 0) {
      _drawPicture(canvas, current, f.inAlpha, f.inScale, f.inDx, w, h);
    }
    _wash.color = paints.veil;
    canvas.drawRect(all, _wash);
    if (f.dip > 0) {
      _wash.color = paints.veil.withValues(alpha: f.dip);
      canvas.drawRect(all, _wash);
    }
    if (f.sweep >= 0 && f.sweepAlpha > 0) _drawSweep(canvas, f, w, h);
    if (f.cover > 0) _drawFog(canvas, f.cover, w, h);
    if (f.flash > 0) {
      _wash.color = paints.light.withValues(alpha: 0.95 * f.flash);
      canvas.drawRect(all, _wash);
    }
    if (_pauseAfterRender) {
      _pauseAfterRender = false;
      if (!paused) pauseEngine();
    }
  }

  /// Cover-fit, about the centre, scaled and nudged by the frame.
  void _drawPicture(
    ui.Canvas canvas,
    ui.Image image,
    double alpha,
    double scale,
    double dx,
    double w,
    double h,
  ) {
    final s = math.max(w / image.width, h / image.height) * scale;
    final dw = image.width * s;
    final dh = image.height * s;
    // theme-keep: white modulates the picture's own colours by alpha only.
    _picture.color = Colors.white.withValues(alpha: alpha);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH((w - dw) / 2 + dx * w, (h - dh) / 2, dw, dh),
      _picture,
    );
  }

  /// A soft band of light leaning back, crossing left to right.
  void _drawSweep(ui.Canvas canvas, SceneMoveFrame f, double w, double h) {
    final cx = -0.3 * w + f.sweep * 1.6 * w;
    final half = 0.15 * w;
    final light = paints.light.withValues(alpha: f.sweepAlpha);
    final clear = paints.light.withValues(alpha: 0);
    _sweep.shader = ui.Gradient.linear(
      ui.Offset(-half, 0),
      ui.Offset(half, 0),
      [clear, light, clear],
    );
    canvas
      ..save()
      ..translate(cx, h / 2)
      ..rotate(-0.35)
      ..drawRect(
        ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: half * 2,
          height: h * 2,
        ),
        _sweep,
      )
      ..restore();
    _sweep.shader?.dispose();
    _sweep.shader = null;
  }

  /// A wash that thickens with the cover and the banks rolling in from
  /// both sides to meet past the middle. The banks' gradients are built
  /// per frame; the roll lasts two seconds and nothing else is moving.
  void _drawFog(ui.Canvas canvas, double cover, double w, double h) {
    _wash.color = paints.fog.withValues(alpha: sceneFogWash(cover));
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w, h), _wash);
    final span = math.max(w, h);
    final thick = paints.fog.withValues(alpha: 0.95 * cover);
    final clear = paints.fog.withValues(alpha: 0);
    for (final bank in _banks) {
      final centre = ui.Offset(sceneFogBankX(bank, cover) * w, bank.y * h);
      final r = bank.r * span;
      final shader = ui.Gradient.radial(centre, r, [thick, clear]);
      _wash.shader = shader;
      canvas.drawCircle(centre, r, _wash);
      _wash.shader = null;
      shader.dispose();
    }
  }
}
