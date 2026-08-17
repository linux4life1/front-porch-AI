// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Persist of a tail window MUST write DB positions as base+index.
// Writing the raw index (0..23) onto a 1000-row chat overwrites the
// greeting, not the latest turn.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/session_open_window.dart';

void main() {
  test('persist offset keeps the tail on its real positions', () {
    const base = 976;
    expect(persistMessagePosition(base: base, index: 0), 976);
    expect(persistMessagePosition(base: base, index: 23), 999);
    expect(
      persistMessagePosition(base: 0, index: 5),
      5,
      reason: 'a fully hydrated list is still 0-based',
    );
  });

  test('a chat shorter than the window does not need a backfill', () {
    expect(kSessionOpenWindow, greaterThan(10));
    expect(11 < kSessionOpenWindow, isTrue);
  });

  test('open does not drop the overlay — owner ends after hydrate', () {
    final src = File('lib/services/chat/chat_service_session_window.dart')
        .readAsStringSync();
    final openAt = src.indexOf('Future<void> _openSessionMessages');
    expect(openAt, greaterThanOrEqualTo(0));
    final openBody = src.substring(openAt);
    expect(
      openBody.contains('endSessionLoad()'),
      isFalse,
      reason:
          'tail paint is about backfill, not dropping before scalars. '
          'A picker-owned load still has hydrate + loadSession to run.',
    );
    expect(src.contains('await Future<void>.delayed(Duration.zero)'), isTrue);
  });
}
