// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/world_ref_resolver.dart';

void main() {
  group('resolveWorldRefsToIds', () {
    test('resolves names and keeps ids', () {
      final unresolved = <String>[];
      final ids = resolveWorldRefsToIds(
        refs: ['uuid-1', 'Mars', 'missing', 'uuid-1'],
        nameToId: {'Mars': 'uuid-mars'},
        validIds: {'uuid-1', 'uuid-mars'},
        unresolved: unresolved,
      );
      expect(ids, ['uuid-1', 'uuid-mars']);
      expect(unresolved, ['missing']);
    });
  });

  group('uniqueWorldName', () {
    test('returns base when free, then (2)', () {
      final taken = {'Mars'};
      expect(uniqueWorldName('Earth', taken.contains), 'Earth');
      expect(uniqueWorldName('Mars', taken.contains), 'Mars (2)');
    });
  });
}
