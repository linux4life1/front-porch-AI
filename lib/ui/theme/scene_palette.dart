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

import 'package:flutter/material.dart';

/// The Ambient Stage's weather washes: the colours the stage paints over
/// the chat background for a part of day, a weather condition and a
/// temperature band. Data, keyed by the story clock's six periods, the
/// weather engine's condition names and its temperature band names, so the
/// theme stays free of the chat services. `SceneSim` turns these into
/// tokens; `docs/design/ambient-stage.md` is the design.
///
/// Every wash is translucent and paints behind the bubbles, never over
/// them. The light-mode scale keeps the chat's own canvas text readable on
/// paper, pinned by `scene_sim_test`.
@immutable
class SceneWash {
  const SceneWash(this.color, this.alpha);

  /// A solid hue; [alpha] is applied by the stage.
  final Color color;
  final double alpha;

  static const SceneWash none = SceneWash(Color(0xFFFFFFFF), 0);
}

/// A condition's wash plus how much it darkens the scene and how much haze
/// it lays over it.
@immutable
class SceneConditionWash {
  const SceneConditionWash({
    required this.wash,
    required this.darken,
    required this.haze,
  });

  final SceneWash wash;

  /// A black wash under the colour wash, 0 to 1.
  final double darken;

  /// A pale radial haze, 0 (none) to 1 (fog).
  final double haze;
}

/// The part-of-day wash, by the story clock's period key.
const Map<String, SceneWash> kSceneDaypartWash = {
  'dawn': SceneWash(Color(0xFFF2A07B), 0.14),
  'morning': SceneWash(Color(0xFFFFE9C4), 0.08),
  'late_morning': SceneWash.none,
  'afternoon': SceneWash(Color(0xFFFFF3D6), 0.05),
  'evening': SceneWash(Color(0xFFE8913F), 0.14),
  'night': SceneWash(Color(0xFF122A4A), 0.32),
};

/// The condition wash, by `WeatherCondition.name`.
const Map<String, SceneConditionWash> kSceneConditionWash = {
  'clear': SceneConditionWash(wash: SceneWash.none, darken: 0, haze: 0),
  'cloudy': SceneConditionWash(
    wash: SceneWash(Color(0xFF9AA3AD), 0.08),
    darken: 0.08,
    haze: 0,
  ),
  'overcast': SceneConditionWash(
    wash: SceneWash(Color(0xFF7D858E), 0.16),
    darken: 0.18,
    haze: 0.05,
  ),
  // Haze 0.80 (not 0.85) keeps High Contrast dark above its 7:1
  // floor in the worst cell (dawn, cryogenic); `scene_sim_test` pins it.
  'fog': SceneConditionWash(
    wash: SceneWash(Color(0xFFC9CED3), 0.10),
    darken: 0.05,
    haze: 0.80,
  ),
  'rain': SceneConditionWash(
    wash: SceneWash(Color(0xFF4B5B6E), 0.14),
    darken: 0.22,
    haze: 0.10,
  ),
  'storm': SceneConditionWash(
    wash: SceneWash(Color(0xFF1F2A38), 0.26),
    darken: 0.38,
    haze: 0.15,
  ),
  'snow': SceneConditionWash(
    wash: SceneWash(Color(0xFFDFE9F2), 0.10),
    darken: 0.06,
    haze: 0.20,
  ),
};

/// The temperature cast, by `TempBand.name`. Mild adds nothing.
const Map<String, SceneWash> kSceneTempCast = {
  'cryogenic': SceneWash(Color(0xFF7FD3FF), 0.10),
  'cold': SceneWash(Color(0xFF9EC5E8), 0.08),
  'cool': SceneWash(Color(0xFFBCD7E8), 0.04),
  'mild': SceneWash.none,
  'warm': SceneWash(Color(0xFFFFD39B), 0.04),
  'hot': SceneWash(Color(0xFFFF9F5A), 0.08),
  'furnace': SceneWash(Color(0xFFFF6A2A), 0.14),
  'inferno': SceneWash(Color(0xFFFF3B1A), 0.20),
};

/// The haze colour, one tone in both modes.
const Color kSceneHaze = Color(0xFFCDD2D8);

/// The darkening wash under a condition.
const Color kSceneShade = Color(0xFF0A0E14);

/// On a light theme the canvas is paper, so every wash is scaled down to
/// keep the chat's own text readable; `scene_sim_test` pins the floor.
const double kSceneLightModeScale = 0.45;
