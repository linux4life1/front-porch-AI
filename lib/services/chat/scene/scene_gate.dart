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
import '../weather_engine.dart';
import '../weather_segments.dart';
import 'scene_tokens.dart';

/// The Ambient Stage's product rule, as a pure function: whether there is a
/// scene to paint and which weather it shows. `sceneTokensFor` and
/// `sceneWireFor` forward here, so the desktop stage and the web chat state
/// cannot disagree, and `scene_sim_test` pins every case.
class SceneGate {
  SceneGate._();

  /// Null when Ambient scene is Off, or when there is no day weather (no
  /// world with climate on, weather off, or the clock not running; the
  /// chat's `currentWeather` is already null for all of those). Otherwise
  /// the scene shows the segment's condition when there is one, else the
  /// day's, at the day's temperature band.
  static SceneTokens? resolve({
    required AmbientScene level,
    required DailyWeather? day,
    SegmentWeather? segment,
    required String daypart,
    required bool dark,
  }) {
    if (level == AmbientScene.off || day == null) return null;
    return SceneSim.resolve(
      daypart: daypart,
      condition: segment?.condition ?? day.condition,
      temp: day.temp,
      dark: dark,
    );
  }
}
