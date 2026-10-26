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

import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Colors;

import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/ui/theme/scene_palette.dart';
import 'scene_precipitation.dart';
import 'scene_sky_layers.dart';

/// The Ambient Stage: a Flame game behind the chat column that paints the
/// story's weather. The tint is always there; at Tint and effects the
/// clouds, fog, rain or snow and the storm flash join it, drawn from one
/// plain-Dart [SceneEffectsSim] that the game steps each frame
/// (`docs/design/ambient-stage.md`). Every colour comes in through
/// [SceneTokens]; nothing here picks one.
class AmbientStageGame extends FlameGame {
  AmbientStageGame(SceneTokens tokens) : _tokens = tokens {
    // Pause belongs to AmbientStage, which knows whether the stage animates
    // (lifecycle, focus, reduce motion, generating); Flame's own
    // backgrounding rule would resume a static stage behind its back.
    pauseWhenBackgrounded = false;
  }

  SceneTokens _tokens;
  SceneTintComponent? _tint;
  SceneEffectsSim? _effects;
  List<Component> _effectLayers = const [];
  final StreamController<SceneFlash> _flashes =
      StreamController<SceneFlash>.broadcast();

  /// While true the weather holds still where it is (a static stage, as
  /// under reduce motion): the stage still paints, the sim is not stepped,
  /// even by [repaintOnce], and no flash fires.
  bool effectsFrozen = false;

  SceneTokens get tokens => _tokens;

  /// The moving weather now, or null at Tint only or when there is none.
  SceneEffectsSim? get effects => _effects;

  /// Each storm flash as it fires, for the scene sound's thunder.
  Stream<SceneFlash> get flashes => _flashes.stream;

  /// Swaps the scene; a value-equal set of tokens is a no-op. The weather
  /// is scattered again only when its seed or kind changes. A paused stage
  /// repaints once so the new scene shows without running the loop.
  set tokens(SceneTokens value) {
    if (value == _tokens) return;
    _tokens = value;
    _tint?.tokens = value;
    _syncEffects();
    repaintOnce();
  }

  /// Paints the current scene once while the engine is paused, without
  /// starting the ticker: [stepEngine] runs one loop step (an update that
  /// mounts pending components, then the render box's markNeedsPaint). A
  /// no-op while the engine runs, since the next tick paints anyway, and
  /// before the render box has its loop, which [onAttach] covers.
  void repaintOnce() {
    if (paused) stepEngine();
  }

  /// The render box attaches in the frame it first paints, before it has a
  /// loop and before any update has mounted the tint (a game renders only
  /// mounted children). A zero-time update here mounts it, so the first
  /// frame is already tinted, paused or not, and moves nothing.
  @override
  void onAttach() {
    super.onAttach();
    update(0);
  }

  /// Transparent: the chat background and the theme ground show through.
  @override
  Color backgroundColor() => Colors.transparent;

  @override
  FutureOr<void> onLoad() {
    final tint = SceneTintComponent(_tokens);
    _tint = tint;
    add(tint);
    _syncEffects();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _syncEffects();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!effectsFrozen) _effects?.advance(dt);
  }

  @override
  void onRemove() {
    unawaited(_flashes.close());
    super.onRemove();
  }

  void _syncEffects() {
    final w = size.x;
    final h = size.y;
    if (!_tokens.hasEffects || w <= 0 || h <= 0) {
      _effects = null;
      if (_effectLayers.isNotEmpty) {
        removeAll(_effectLayers);
        _effectLayers = const [];
      }
      return;
    }
    final current = _effects;
    if (current == null ||
        current.seed != _tokens.seed ||
        current.spec != _tokens.effects ||
        current.width != w ||
        current.height != h) {
      _effects = SceneEffectsSim(
        spec: _tokens.effects,
        seed: _tokens.seed,
        width: w,
        height: h,
        onFlash: _flashes.add,
      );
    }
    if (_effectLayers.isEmpty) {
      _effectLayers = [
        SceneCloudLayer(),
        SceneFogLayer(),
        ScenePrecipitation(),
        SceneLightningFlash(),
      ];
      addAll(_effectLayers);
    }
  }
}

/// The weather washes, full-stage, in [SceneTokens.layers] order, then the
/// haze as a radial wash thin at the centre and thicker at the corners.
class SceneTintComponent extends PositionComponent
    with HasGameReference<AmbientStageGame> {
  SceneTintComponent(this.tokens);

  SceneTokens tokens;

  @override
  void render(Canvas canvas) {
    final size = game.size;
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final paint = Paint();
    for (final layer in tokens.layers) {
      paint.color = layer.paint;
      canvas.drawRect(rect, paint);
    }
    if (tokens.haze > 0) {
      // The web's `radial-gradient(circle at center, centre 15%, edge
      // 100%)`: a circle whose radius reaches the farthest corner.
      final centre = Offset(size.x / 2, size.y / 2);
      final radius = centre.distance;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.radial(
            centre,
            radius,
            [
              kSceneHaze.withValues(alpha: tokens.hazeCentreAlpha),
              kSceneHaze.withValues(alpha: tokens.hazeEdgeAlpha),
            ],
            const [0.15, 1.0],
          ),
      );
    }
  }
}
