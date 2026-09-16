// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window chrome for [window_manager].
///
/// Flutter 3.47 made Impeller the default desktop renderer and turned on
/// wide-gamut on macOS. `WindowOptions.backgroundColor: Colors.transparent`
/// plus window_manager's macOS `setTitleBarStyle` (which always sets
/// `isOpaque = false`) then made AppKit treat the title bar as a clear
/// strip — traffic lights sat on the same charcoal as the body.
///
/// Keep this opaque + [TitleBarStyle.normal]. Do not switch to
/// [TitleBarStyle.hidden] or a transparent background without a replacement
/// native title bar. Windows/Linux keep the same options so they stay a
/// normal decorated window.
WindowOptions mainWindowOptions({Size? size}) {
  return WindowOptions(
    size: size ?? const Size(1280, 720),
    center: true,
    backgroundColor: AppColors.background,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    windowButtonVisibility: true,
    title: 'Front Porch AI',
  );
}
