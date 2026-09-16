// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/window_chrome.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  test('main window chrome is an opaque native title bar', () {
    final options = mainWindowOptions();
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

  test('forced size still keeps the opaque title bar', () {
    final options = mainWindowOptions(size: const Size(800, 600));
    expect(options.size, const Size(800, 600));
    expect(options.titleBarStyle, TitleBarStyle.normal);
    expect(options.backgroundColor!.a, 1.0);
    expect(options.windowButtonVisibility, isTrue);
  });

  // Deleting the helper call and inlining Colors.transparent would leave
  // the two tests above green. This reads the real startup call site.
  test('_showMainWindow uses mainWindowOptions, not a transparent bar', () {
    final startup = File('lib/main.startup.dart').readAsStringSync();
    expect(startup, contains('mainWindowOptions(size: forcedSize)'));
    expect(startup, isNot(contains('Colors.transparent')));
    expect(startup, contains('TitleBarStyle.normal'));
    final swift = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    expect(swift, contains('applyOpaqueTitleBar'));
    expect(swift, contains('titlebarAppearsTransparent = false'));
    expect(swift, contains('fullSizeContentView'));
  });
}
