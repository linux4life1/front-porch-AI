// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regenerating a departed Scene Guest's bubble must refuse BEFORE journal
// invalidation. Invalidating first killed cites for a message still on
// screen, with no replant.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guest-left regen refuses before journal invalidation', () {
    final src = File('lib/services/chat/chat_service_reprocess.dart')
        .readAsStringSync();
    final start = src.indexOf('regenerateLastMessage');
    expect(start, greaterThanOrEqualTo(0));
    final body = src.substring(start);
    final guestLeft = body.indexOf(
      'regenGuest == null && _isGuestAuthoredMessage(lastMsg)',
    );
    final invalidate = body.indexOf('_invalidateJournalFrom(');
    expect(guestLeft, greaterThanOrEqualTo(0));
    expect(
      invalidate,
      greaterThan(guestLeft),
      reason: 'invalidating first drops journal cites for a bubble we put back',
    );
  });
}
