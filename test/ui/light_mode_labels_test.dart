// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Light mode: New Chat Cancel was Colors.white54 and Create Character
// Advanced Prompts was white38/white54 — both vanish on warm paper.
//
// Proven red: restore Colors.white54 on those labels and the scans fail.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('New Chat Cancel is not hard-coded white', () {
    final src = File(
      'lib/ui/pages/chat_page.session_dialogs.dart',
    ).readAsStringSync();
    expect(src, contains('warmDialogCancel(context)'));
    expect(
      src,
      isNot(contains("style: TextStyle(color: Colors.white54)")),
      reason: 'THE BUG: Cancel is white-on-paper in light mode',
    );
  });

  test('Create Character Advanced Prompts uses AppColors, not white54', () {
    final src = File(
      'lib/ui/pages/create_character_page.steps_core.dart',
    ).readAsStringSync();
    expect(src, contains('Advanced Prompts (optional)'));
    expect(src, contains('AppColors.textSecondary(context)'));
    expect(src, contains('AppColors.iconSecondary(context)'));
    expect(
      src,
      isNot(contains('Colors.white54')),
      reason: 'THE BUG: Advanced Prompts is white-on-paper in light mode',
    );
    expect(src, isNot(contains('Colors.white38')));
  });
}
