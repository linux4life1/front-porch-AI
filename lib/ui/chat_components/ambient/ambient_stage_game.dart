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
import 'package:flutter/foundation.dart' show visibleForTesting;
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
  /// starting the ticker: [stepEngine] runs one zero-time loop step (an
  /// update that mounts pending components and moves nothing, so a stage
  /// paused mid-weather keeps its drops where they are, then the render
  /// box's markNeedsPaint). A no-op while the engine runs, since the next
  /// tick paints anyway, and before the render box has its loop, which
  /// [onAttach] covers.
  void repaintOnce() {
    if (paused) stepEngine(stepTime: 0);
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

  /// The GameWidget calls this on the game alone when it goes away
  /// (`Game.finalizeRemoval`), never on the children. `FlameGame.dispose`
  /// walks them but also clears Flame's global image and asset caches, so
  /// its first two steps are run here instead, while the game is still
  /// mounted: every child's onRemove fires, freeing the tint's picture and
  /// the fog's shaders now rather than at the next GC.
  @override
  void onRemove() {
    removeAll(children);
    processLifecycleEvents();
    _tint = null;
    _effects = null;
    _effectLayers = const [];
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
///
/// The washes change only with the scene or the stage size, but an
/// animated stage renders every frame, so they are recorded once into a
/// picture and replayed: a frame makes no paint and no shader.
class SceneTintComponent extends PositionComponent
    with HasGameReference<AmbientStageGame> {
  SceneTintComponent(SceneTokens tokens) : _tokens = tokens;

  SceneTokens _tokens;
  Picture? _picture;
  Size _pictureSize = Size.zero;

  /// How many times the washes have been recorded, for tests.
  @visibleForTesting
  int debugRebuilds = 0;

  /// Whether a recording is held now, for tests.
  @visibleForTesting
  bool get debugHasPicture => _picture != null;

  SceneTokens get tokens => _tokens;

  /// A different scene drops the recording; the next render records anew.
  set tokens(SceneTokens value) {
    if (value == _tokens) return;
    _tokens = value;
    _dropPicture();
  }

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    var picture = _picture;
    if (picture == null ||
        w != _pictureSize.width ||
        h != _pictureSize.height) {
      _dropPicture();
      _pictureSize = Size(w, h);
      picture = _record(_pictureSize);
      _picture = picture;
    }
    canvas.drawPicture(picture);
  }

  @override
  void onRemove() {
    _dropPicture();
    super.onRemove();
  }

  void _dropPicture() {
    _picture?.dispose();
    _picture = null;
  }

  Picture _record(Size size) {
    debugRebuilds++;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    final paint = Paint();
    for (final layer in _tokens.layers) {
      paint.color = layer.paint;
      canvas.drawRect(rect, paint);
    }
    if (_tokens.haze > 0) {
      // The web's `radial-gradient(circle at center, centre 15%, edge
      // 100%)`: a circle whose radius reaches the farthest corner.
      // A fresh paint: a shader is modulated by its paint's alpha, and the
      // shared one still carries the last wash's.
      final centre = size.center(Offset.zero);
      final haze = Paint()
        ..shader = Gradient.radial(
          centre,
          centre.distance,
          [
            kSceneHaze.withValues(alpha: _tokens.hazeCentreAlpha),
            kSceneHaze.withValues(alpha: _tokens.hazeEdgeAlpha),
          ],
          const [0.15, 1.0],
        );
      canvas.drawRect(rect, haze);
    }
    return recorder.endRecording();
  }
}
