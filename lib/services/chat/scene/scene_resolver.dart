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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'scene_tokens.dart';

/// The scene for the open chat, or null when the stage has nothing to
/// paint: Ambient scene is Off, or the chat has no weather (no world with
/// climate on, weather off, or the clock not running; [currentWeather] is
/// already null for all of those). Read live by the desktop stage and the
/// web chat state, so both surfaces agree.
SceneTokens? sceneTokensFor(ChatService chat, StorageService storage) {
  final appearance = storage.appearance;
  if (appearance.ambientScene == AmbientScene.off) return null;
  final day = chat.currentWeather;
  if (day == null) return null;
  final segment = chat.currentSegmentWeather;
  return SceneSim.resolve(
    daypart: chat.timeService.timeOfDay,
    condition: segment?.condition ?? day.condition,
    temp: day.temp,
    dark: appearance.isDark,
  );
}
