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

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:front_porch_ai/ui/theme/themes/app_theme_id.dart';
import 'scene_effects.dart';
import 'scene_rng.dart';
import 'scene_tokens.dart';

/// The scene for the open chat, or null when the stage has nothing to
/// paint: Ambient scene is Off, or the chat has no weather (no world with
/// climate on, weather off, or the clock not running; [currentWeather] is
/// already null for all of those). Read live by the desktop stage and the
/// web chat state, so both surfaces agree.
SceneTokens? sceneTokensFor(ChatService chat) {
  final appearance = chat.appearance;
  final level = sceneLevelFor(appearance.ambientScene, appearance.theme);
  if (level == null) return null;
  final day = chat.currentWeather;
  final session = chat.currentSessionId;
  if (day == null || session == null) return null;
  final daypart = chat.timeService.timeOfDay;
  final condition = chat.currentSegmentWeather?.condition ?? day.condition;
  return SceneSim.resolve(
    daypart: daypart,
    condition: condition,
    temp: day.temp,
    dark: appearance.isDark,
    level: level,
    // The weather engine's own inputs: the chat and the story day.
    seed: sceneSeed(
      sessionSeed: session,
      dayCount: chat.timeService.dayCount,
      daypart: daypart,
      condition: condition.name,
    ),
    pauseWhileGenerating: appearance.pauseEffectsWhileGenerating,
  );
}

/// How much of the scene the stage paints for an Ambient scene choice on a
/// theme, or null for Off. High Contrast holds it to Tint only: moving
/// weather behind the text is what that theme is chosen to avoid.
SceneLevel? sceneLevelFor(AmbientScene scene, AppThemeId theme) =>
    switch (scene) {
      AmbientScene.off => null,
      AmbientScene.tint => SceneLevel.tint,
      AmbientScene.effects =>
        theme == AppThemeId.highContrast ? SceneLevel.tint : SceneLevel.effects,
    };
