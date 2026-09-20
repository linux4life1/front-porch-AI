// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/window_chrome.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  test('macOS window chrome is an opaque native title bar', () {
    final options = mainWindowOptions(isMacOS: true);
    expect(options.titleBarStyle, TitleBarStyle.normal);
    expect(options.windowButtonVisibility, isTrue);
    expect(options.backgroundColor, isNotNull);
    expect(options.backgroundColor!.a, 1.0);
    expect(options.backgroundColor, AppColors.background);
    expect(options.title, 'Front Porch AI');
    expect(options.size, const Size(1280, 720));
    expect(options.center, isTrue);
    expect(options.skipTaskbar, isFalse);
  });

  test('Windows and Linux chrome is not opaque porch charcoal', () {
    final options = mainWindowOptions(isMacOS: false);
    expect(options.titleBarStyle, TitleBarStyle.normal);
    expect(options.windowButtonVisibility, isTrue);
    expect(options.backgroundColor, isNot(AppColors.background));
    expect(
      options.backgroundColor == null || options.backgroundColor!.a < 1.0,
      isTrue,
      reason: 'Win/Linux must not paint porch charcoal on the native window',
    );
    expect(options.title, 'Front Porch AI');
    expect(
      mainWindowOptions(isMacOS: true).backgroundColor,
      isNot(options.backgroundColor),
    );
  });

  test('forced size still keeps the platform title-bar rules', () {
    final mac = mainWindowOptions(size: const Size(800, 600), isMacOS: true);
    expect(mac.size, const Size(800, 600));
    expect(mac.titleBarStyle, TitleBarStyle.normal);
    expect(mac.backgroundColor, AppColors.background);
    expect(mac.backgroundColor!.a, 1.0);
    expect(mac.windowButtonVisibility, isTrue);

    final win = mainWindowOptions(size: const Size(800, 600), isMacOS: false);
    expect(win.size, const Size(800, 600));
    expect(win.titleBarStyle, TitleBarStyle.normal);
    expect(win.backgroundColor, isNot(AppColors.background));
    expect(win.backgroundColor == null || win.backgroundColor!.a < 1.0, isTrue);
    expect(win.windowButtonVisibility, isTrue);
  });

  test('host default follows this OS without requiring a Mac host', () {
    final options = mainWindowOptions();
    if (Platform.isMacOS) {
      expect(options.backgroundColor, AppColors.background);
      expect(options.backgroundColor!.a, 1.0);
    } else {
      expect(options.backgroundColor, isNot(AppColors.background));
      expect(
        options.backgroundColor == null || options.backgroundColor!.a < 1.0,
        isTrue,
      );
    }
    expect(options.titleBarStyle, TitleBarStyle.normal);
    expect(options.windowButtonVisibility, isTrue);
  });
}
