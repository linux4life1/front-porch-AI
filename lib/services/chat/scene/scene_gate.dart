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

import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:front_porch_ai/ui/theme/themes/app_theme_id.dart';
import '../weather_engine.dart';
import '../weather_segments.dart';
import 'scene_effects.dart';
import 'scene_rng.dart';
import 'scene_tokens.dart';

/// The Ambient Stage's product rule, as a pure function: whether there is a
/// scene to paint, how much of it, and which weather it shows.
/// `sceneTokensFor` and `sceneWireFor` forward here, so the desktop stage
/// and the web chat state cannot disagree; `scene_sim_test` and
/// `scene_effects_test` pin every case.
class SceneGate {
  SceneGate._();

  /// Null when Ambient scene is Off, or when there is no day weather (no
  /// world with climate on, weather off, or the clock not running; the
  /// chat's `currentWeather` is already null for all of those). Otherwise
  /// the scene shows the segment's condition when there is one, else the
  /// day's, at the day's temperature band, at the level [sceneLevelFor]
  /// allows on [theme]. At Tint and effects the moving weather is scattered
  /// from the chat ([sessionSeed]) and the story day, the weather engine's
  /// own inputs; at Tint only nothing moves, so the seed stays 0.
  ///
  /// [level] is the user's Ambient scene choice. [theme], [sessionSeed],
  /// [dayCount] and [pauseWhileGenerating] came with the effects and default
  /// so a tint-only caller reads as before; the app passes all of them. A
  /// null [theme] applies no theme cap.
  static SceneTokens? resolve({
    required AmbientScene level,
    AppThemeId? theme,
    required DailyWeather? day,
    SegmentWeather? segment,
    required String daypart,
    required bool dark,
    String sessionSeed = '',
    int dayCount = 0,
    bool pauseWhileGenerating = true,
  }) {
    final allowed = sceneLevelFor(level, theme);
    if (allowed == null || day == null) return null;
    final condition = segment?.condition ?? day.condition;
    return SceneSim.resolve(
      daypart: daypart,
      condition: condition,
      temp: day.temp,
      dark: dark,
      level: allowed,
      seed: allowed == SceneLevel.effects
          ? sceneSeed(
              sessionSeed: sessionSeed,
              dayCount: dayCount,
              daypart: daypart,
              condition: condition.name,
            )
          : 0,
      pauseWhileGenerating: pauseWhileGenerating,
    );
  }
}

/// How much of the scene the stage paints for an Ambient scene choice on a
/// theme, or null for Off. High Contrast holds it to Tint only: moving
/// weather behind the text is what that theme is chosen to avoid. A null
/// [theme] applies no cap.
SceneLevel? sceneLevelFor(AmbientScene scene, AppThemeId? theme) =>
    switch (scene) {
      AmbientScene.off => null,
      AmbientScene.tint => SceneLevel.tint,
      AmbientScene.effects =>
        theme == AppThemeId.highContrast ? SceneLevel.tint : SceneLevel.effects,
    };
