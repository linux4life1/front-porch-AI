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
import 'scene_gate.dart';
import 'scene_tokens.dart';

/// The scene the desktop stage paints for the open chat, in the app's own
/// brightness, or null when there is nothing to paint ([SceneGate.resolve]).
SceneTokens? sceneTokensFor(ChatService chat) =>
    _sceneAt(chat, dark: chat.appearance.isDark);

/// The chat state's `scene` for the web: the same scene in both
/// brightnesses, because the PWA may run its own mode. Null when there is
/// nothing to paint.
Map<String, Object>? sceneWireFor(ChatService chat) {
  final dark = _sceneAt(chat, dark: true);
  final light = _sceneAt(chat, dark: false);
  if (dark == null || light == null) return null;
  return SceneTokens.wireOf(dark: dark, light: light);
}

SceneTokens? _sceneAt(ChatService chat, {required bool dark}) =>
    SceneGate.resolve(
      level: chat.appearance.ambientScene,
      day: chat.currentWeather,
      segment: chat.currentSegmentWeather,
      daypart: chat.timeService.timeOfDay,
      dark: dark,
    );
