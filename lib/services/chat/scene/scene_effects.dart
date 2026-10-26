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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/ui/theme/scene_palette.dart';

/// How much of the scene the stage paints: the wash alone, or the wash and
/// the moving weather. Off never reaches the stage (it is not mounted).
enum SceneLevel {
  tint,
  effects;

  /// The wire value.
  String get key => name;
}

/// What falls or drifts across the stage for a condition.
enum SceneEffectKind { none, rain, snow, clouds, fog }

/// Particles never exceed this, however big the window: a few hundred in one
/// batch is trivial for a GPU, and a local model shares that GPU.
const int kSceneParticleCap = 400;

/// Fog blobs drift over the stage when the condition's haze passes
/// [kSceneFogHazeFloor].
const int kSceneFogBlobs = 7;
const double kSceneFogHazeFloor = 0.3;

/// The moving weather for one condition. Budgets scale with the stage's
/// area through [density]; [particlesFor] applies the cap. The web twin
/// reads these from the wire rather than keeping its own table.
@immutable
class SceneEffectSpec {
  const SceneEffectSpec({
    required this.kind,
    this.density = 0,
    this.clouds = 0,
    this.fog = false,
    this.lightning = false,
    this.wind = 0,
  });

  /// Rain, snow, or the shapes alone (clouds, fog), or nothing.
  final SceneEffectKind kind;

  /// Particles per square logical pixel of stage.
  final double density;

  /// Cloud shapes along the top of the stage.
  final int clouds;

  /// Whether drifting fog blobs are painted.
  final bool fog;

  /// Whether the storm flash runs.
  final bool lightning;

  /// Rain's sideways slant, as a fraction of its fall speed.
  final double wind;

  static const SceneEffectSpec none = SceneEffectSpec(
    kind: SceneEffectKind.none,
  );

  /// The draft numbers from the design's prototype, by
  /// `WeatherCondition.name`; an unknown condition paints nothing.
  static SceneEffectSpec forCondition(String condition) {
    final fog =
        (kSceneConditionWash[condition]?.haze ?? 0) > kSceneFogHazeFloor;
    return switch (condition) {
      'cloudy' => const SceneEffectSpec(
        kind: SceneEffectKind.clouds,
        clouds: 5,
      ),
      'overcast' => const SceneEffectSpec(
        kind: SceneEffectKind.clouds,
        clouds: 9,
      ),
      'fog' => SceneEffectSpec(kind: SceneEffectKind.fog, fog: fog),
      'rain' => SceneEffectSpec(
        kind: SceneEffectKind.rain,
        density: 0.00035,
        clouds: 6,
        fog: fog,
        wind: 0.18,
      ),
      'storm' => SceneEffectSpec(
        kind: SceneEffectKind.rain,
        density: 0.00065,
        clouds: 9,
        fog: fog,
        lightning: true,
        wind: 0.42,
      ),
      'snow' => SceneEffectSpec(
        kind: SceneEffectKind.snow,
        density: 0.00022,
        clouds: 5,
        fog: fog,
      ),
      _ => none,
    };
  }

  /// The particle count for a stage of [width] by [height] logical pixels.
  int particlesFor(double width, double height) {
    final n = (width * height * density).round();
    return n < kSceneParticleCap ? n : kSceneParticleCap;
  }

  /// Whether anything moves at all.
  bool get isEmpty => density == 0 && clouds == 0 && !fog;

  Map<String, Object> toWire() => {
    'kind': kind.name,
    'density': density,
    'clouds': clouds,
    'fog': fog,
    'lightning': lightning,
    'wind': wind,
  };

  @override
  bool operator ==(Object other) =>
      other is SceneEffectSpec &&
      other.kind == kind &&
      other.density == density &&
      other.clouds == clouds &&
      other.fog == fog &&
      other.lightning == lightning &&
      other.wind == wind;

  @override
  int get hashCode => Object.hash(kind, density, clouds, fog, lightning, wind);
}
