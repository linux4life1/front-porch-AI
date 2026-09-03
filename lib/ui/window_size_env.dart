// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Compile-time launch hook (`--dart-define=WINDOW_WIDTH=800` /
/// `--dart-define=WINDOW_HEIGHT=600`).
///
/// 0 (the product default) is unset. When either axis is >0, startup skips
/// saved-bounds restore and sets the window to the defined size (missing
/// axis is 1280 or 720). Close must not write `window_width` /
/// `window_height` prefs while this is active — that would poison the
/// user's saved window.
class WindowSizeEnv {
  WindowSizeEnv._();

  static Size? sizeFromEnvironment({
    int width = const int.fromEnvironment('WINDOW_WIDTH', defaultValue: 0),
    int height = const int.fromEnvironment('WINDOW_HEIGHT', defaultValue: 0),
  }) {
    if (width <= 0 && height <= 0) return null;
    return Size(
      (width > 0 ? width : 1280).toDouble(),
      (height > 0 ? height : 720).toDouble(),
    );
  }

  static bool get active => sizeFromEnvironment() != null;
}
