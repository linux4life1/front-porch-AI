// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phase 0 of the "one chat, changing cast" unification: every group member is
// stamped with the library character it was copied from (provenance), stored in
// the Forge-invisible memberState blob (no DB migration). These tests pin the
// encode/getter contract that all three creation sites rely on.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/group_member.dart';

GroupMember _member(Map<String, dynamic> state) =>
    GroupMember(id: 'm1', groupId: 'g1', name: 'Aria', memberState: state);

void main() {
  group('GroupMember provenance (Phase 0)', () {
    test('encodeProvenance + getters round-trip stableId + dbId', () {
      final json = GroupMember.encodeProvenance(
        originStableId: 'aria_card',
        originLibraryDbId: 'db-123',
      );
      final m = _member(jsonDecode(json) as Map<String, dynamic>);
      expect(m.originStableId, 'aria_card');
      expect(m.originLibraryDbId, 'db-123');
    });

    test('encodeProvenance trims and omits blank/null values', () {
      expect(GroupMember.encodeProvenance(originStableId: null), '{}');
      expect(GroupMember.encodeProvenance(originStableId: '   '), '{}');

      // stableId present (with surrounding whitespace), dbId absent →
      // only a trimmed stableId is stamped.
      final json = GroupMember.encodeProvenance(originStableId: '  aria_card  ');
      final m = _member(jsonDecode(json) as Map<String, dynamic>);
      expect(m.originStableId, 'aria_card');
      expect(m.originLibraryDbId, isNull);
    });

    test('legacy empty memberState yields null provenance (back-compat)', () {
      final m = _member(const {});
      expect(m.originStableId, isNull);
      expect(m.originLibraryDbId, isNull);
    });

    test('getters tolerate non-string / empty-string values', () {
      expect(_member(const {'originStableId': 42}).originStableId, isNull);
      expect(_member(const {'originStableId': ''}).originStableId, isNull);
      expect(_member(const {'originLibraryDbId': 7}).originLibraryDbId, isNull);
    });
  });
}
