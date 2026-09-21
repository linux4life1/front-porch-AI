// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window chrome for [window_manager]. Desktop-only — the PWA never
/// calls this (window_manager is not on web).
///
/// Flutter 3.47 made Impeller the default desktop renderer and turned on
/// wide-gamut on macOS. `WindowOptions.backgroundColor: Colors.transparent`
/// plus window_manager's macOS `setTitleBarStyle` (which always sets
/// `isOpaque = false`) then made AppKit treat the title bar as a clear
/// strip — traffic lights sat on the same charcoal as the body.
///
/// macOS keeps this opaque + [TitleBarStyle.normal]. Do not switch Mac to
/// [TitleBarStyle.hidden] or a transparent background without a replacement
/// native title bar. Windows/Linux must NOT paint [AppColors.background] onto
/// the native window — that makes caption buttons low-contrast and kills
/// hover. They stay a normal decorated window with a transparent background.
///
/// [isMacOS] is a test override so Linux CI can pin both branches.
WindowOptions mainWindowOptions({Size? size, bool? isMacOS}) {
  final mac = isMacOS ?? Platform.isMacOS;
  return WindowOptions(
    size: size ?? const Size(1280, 720),
    center: true,
    backgroundColor: mac ? AppColors.background : Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    windowButtonVisibility: true,
    title: 'Front Porch AI',
  );
}
