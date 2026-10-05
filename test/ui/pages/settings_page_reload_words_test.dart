// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A new chat model or preset picked in Settings goes into the running
// KoboldCpp at once. When it could not be loaded (the old model keeps
// running), the page says why in a snackbar, the way a Start says its own,
// instead of dropping the answer.
//
// SettingsPage sits behind the whole provider graph and has no seam to drive
// (see settings_page_launch_state_test.dart), so this reads the call site.
// What the answer holds is pinned where it is made, in
// kobold_reload_keeps_engine_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the chat reload shows the words it is answered with', () {
    final src = File(
      'lib/ui/pages/settings_page.controls.dart',
    ).readAsStringSync();

    final method = RegExp(
      r'void _reloadChatIfRunning\(\) \{.*?\n  \}',
      dotAll: true,
    ).firstMatch(src);
    expect(
      method,
      isNotNull,
      reason:
          'could not read _reloadChatIfRunning — if it moved, move this '
          'guard with it rather than deleting it',
    );
    final body = method!.group(0)!;

    expect(body, contains('reloadChatKobold()'));
    expect(
      body,
      contains('result?.message'),
      reason: 'the answer the reload gives must not be dropped',
    );
    expect(
      body,
      contains('showSnackBar(SnackBar(content: Text(words)))'),
      reason: 'said the way Start says its own reasons',
    );
  });
}
