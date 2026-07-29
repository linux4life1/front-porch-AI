// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';

void main() {
  test('skips worlds with injectDescription false or empty desc', () {
    final text = buildWorldInjection([
      World(
        name: 'Mars',
        description: 'Dust.',
        lorebook: Lorebook(entries: []),
        injectDescription: false,
      ),
      World(
        name: 'Empty',
        description: '  ',
        lorebook: Lorebook(entries: []),
      ),
    ]);
    expect(text, isEmpty);
  });

  test('includes place prose when enabled', () {
    final text = buildWorldInjection([
      World(
        name: 'Mars',
        description: 'Red horizons and thin air.',
        lorebook: Lorebook(entries: []),
        injectDescription: true,
      ),
    ]);
    expect(text, contains('Mars'));
    expect(text, contains('Red horizons'));
    expect(text, startsWith('Setting'));
  });
}
