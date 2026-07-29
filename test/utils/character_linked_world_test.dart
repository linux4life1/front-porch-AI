// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/utils/character_linked_world.dart';

void main() {
  test('detects linked name / id / auto-import description', () {
    expect(
      isCharacterLinkedWorld(
        World(
          name: "Aerin's Lorebook",
          description: 'Auto-imported from character card: Aerin',
          lorebook: Lorebook(entries: []),
        ),
      ),
      isTrue,
    );
    expect(
      isCharacterLinkedWorld(
        World(
          name: 'x',
          lorebook: Lorebook(entries: []),
          linkedCharacterName: 'Aerin',
        ),
      ),
      isTrue,
    );
    expect(
      isCharacterLinkedWorld(
        World(
          name: 'Mars',
          description: 'Red dust.',
          lorebook: Lorebook(entries: []),
        ),
      ),
      isFalse,
    );
  });
}
