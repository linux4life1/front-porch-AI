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
import 'scene_gate.dart';
import 'scene_tokens.dart';

/// The scene the desktop stage paints for the open chat, in the app's own
/// brightness, or null when there is nothing to paint ([SceneGate.resolve]).
SceneTokens? sceneTokensFor(ChatService chat) =>
    _sceneOf(chat)(chat.appearance.isDark);

/// The chat state's `scene` for the web: the same scene in both
/// brightnesses, because the PWA may run its own mode. Null when there is
/// nothing to paint.
Map<String, Object>? sceneWireFor(ChatService chat) {
  final at = _sceneOf(chat);
  final dark = at(true);
  final light = at(false);
  if (dark == null || light == null) return null;
  return SceneTokens.wireOf(dark: dark, light: light);
}

/// Reads the chat once and returns the gate for either brightness. The
/// weather is a walk over the story's days, so it is read once per call
/// (the segment carries its day, the same `currentWeather` value) and not
/// at all when Ambient scene is Off; the chat page's selector and the web
/// snapshot both run this on every notify.
SceneTokens? Function(bool dark) _sceneOf(ChatService chat) {
  final appearance = chat.appearance;
  final segment = appearance.ambientScene == AmbientScene.off
      ? null
      : chat.currentSegmentWeather;
  final daypart = chat.timeService.timeOfDay;
  final sessionSeed = chat.currentSessionId ?? '';
  final dayCount = chat.timeService.dayCount;
  return (dark) => SceneGate.resolve(
    level: appearance.ambientScene,
    theme: appearance.theme,
    day: segment?.day,
    segment: segment,
    daypart: daypart,
    dark: dark,
    // currentWeather is null without a session, so '' never paints.
    sessionSeed: sessionSeed,
    dayCount: dayCount,
    pauseWhileGenerating: appearance.pauseEffectsWhileGenerating,
  );
}
