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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('front_porch_ai/launch_window');

/// The saved theme's window background at the current brightness, read
/// from [prefs] before the first frame.
Color launchBackground(SharedPreferences prefs) {
  final appearance = AppearanceSettings()
    ..initializeBase(prefs, () {})
    ..load();
  return appearance.activePalette.background;
}

/// Paints the native view behind Flutter in [color] before the window is
/// shown, so nothing seen before the first frame is in another theme's
/// colour. macOS and Linux only: the Windows runner stays hidden until the
/// first frame has painted.
Future<void> paintLaunchBackground(Color color) async {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  try {
    await _channel.invokeMethod<void>('setBackground', color.toARGB32());
  } catch (e) {
    debugPrint('[Window] could not set the launch background: $e');
  }
}
