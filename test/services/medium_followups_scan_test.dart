// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Source scans for the 1.3 medium follow-ups that are wiring, not math:
// web Chaos SPIN NOW, Stoop Discussion fail-closed, reunification copies
// group_members with the group row.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web Chaos tools has SPIN NOW posting chance-time/spin', () {
    final src = File('web_ui/src/components/ChatTools.tsx').readAsStringSync();
    expect(src, contains('SPIN NOW'));
    expect(src, contains('/api/chat/chance-time/spin'));
  });

  test('Stoop Discussion treats commentsEnabled as === true (fail-closed)', () {
    final src = File(
      'web_ui/src/pages/stoop/StoopDiscussion.tsx',
    ).readAsStringSync();
    expect(src, contains('detail.commentsEnabled === true'));
    expect(src, contains('setEnabled(false)'));
  });

  test('reunification copies group_members with the group row', () {
    final src = File(
      'lib/services/db_reunification_service.dart',
    ).readAsStringSync();
    expect(src, contains('FROM group_members WHERE group_id'));
    expect(src, contains("'group_members'"));
  });
}
