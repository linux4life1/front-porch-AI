// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Soft-exclude on inter-character writes applies only when the full-member
// set is wired. An empty set is the extracted-leaf default — clamp/create
// must still work. Proven red: restore the unconditional
// `!full.contains(from) || !full.contains(to)` return.

import 'package:flutter_test/flutter_test.dart';

import 'relationship_service_test.dart' show createTestRelationship;

void main() {
  test('leaf update still writes when full-member set is empty', () {
    final svc = createTestRelationship(isGroup: true, groupCharCount: 2);
    svc.updateInterCharacterRelationship('a', 'b', 50);
    expect(svc.getInterCharacterRelationships('a')['b'], 50);
  });

  test('wired full-member set refuses soft / unknown ids', () {
    final svc = createTestRelationship(
      isGroup: true,
      groupCharCount: 2,
      groupMemberIds: {'full-a', 'full-b'},
    );
    svc.updateInterCharacterRelationship('full-a', 'soft-g', 40);
    expect(svc.getInterCharacterRelationships('full-a')['soft-g'], isNull);
    svc.updateInterCharacterRelationship('soft-g', 'full-a', 40);
    expect(svc.getInterCharacterRelationships('soft-g')['full-a'], isNull);
    svc.updateInterCharacterRelationship('full-a', 'full-b', 40);
    expect(svc.getInterCharacterRelationships('full-a')['full-b'], 40);
  });
}
