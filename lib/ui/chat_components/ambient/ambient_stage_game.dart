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

import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/ui/theme/scene_palette.dart';

/// The Ambient Stage: a Flame game behind the chat column that paints the
/// story's weather. This PR it holds one component, the tint; particles,
/// clouds and later sprites are components added beside it
/// (`docs/design/ambient-stage.md`). Every colour comes in through
/// [SceneTokens]; nothing here picks one.
class AmbientStageGame extends FlameGame {
  AmbientStageGame(SceneTokens tokens) : _tokens = tokens;

  SceneTokens _tokens;
  SceneTintComponent? _tint;

  SceneTokens get tokens => _tokens;

  /// Swaps the scene; a value-equal set of tokens is a no-op.
  set tokens(SceneTokens value) {
    if (value == _tokens) return;
    _tokens = value;
    _tint?.tokens = value;
  }

  /// Transparent: the chat background and the theme ground show through.
  @override
  Color backgroundColor() => Colors.transparent;

  @override
  FutureOr<void> onLoad() {
    final tint = SceneTintComponent(_tokens);
    _tint = tint;
    add(tint);
  }
}

/// The weather washes, full-stage, in [SceneTokens.layers] order, then the
/// haze as a radial wash thin at the centre and thicker at the edges.
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
      final centre = Offset(size.x / 2, size.y / 2);
      final radius = (size.x > size.y ? size.x : size.y) * 0.75;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.radial(centre, radius, [
            kSceneHaze.withValues(alpha: tokens.hazeCentreAlpha),
            kSceneHaze.withValues(alpha: tokens.hazeEdgeAlpha),
          ]),
      );
    }
  }
}
