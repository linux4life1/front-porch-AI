// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Open must fetch the newest window first, then page older rows
// backward. Loading 0→current and jumping is the dump-at-first_message
// path.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/session_open_window.dart';

void main() {
  final window = File(
    'lib/services/chat/chat_service_session_window.dart',
  ).readAsStringSync();
  final queries = File(
    'lib/database/database.queries.chat.dart',
  ).readAsStringSync();

  test('open fetches the newest tail, not the 0→current list', () {
    expect(window.contains('getMessagesTailForSession'), isTrue);
    expect(window.contains('kSessionOpenWindow'), isTrue);
    expect(kSessionOpenWindow, 24);
    final open = window
        .split('Future<void> _openSessionMessages')
        .last
        .split('Future<void> _runBackgroundBackfill')
        .first;
    expect(open.contains('getMessagesTailForSession'), isTrue);
    expect(
      open.contains('getMessagesForSession'),
      isFalse,
      reason: 'full 0→current hydrate on open dumps the user at first_message',
    );
  });

  test('backfill pages older rows, never re-fetches 0→current', () {
    final backfill = window
        .split('Future<void> _runBackgroundBackfill')
        .last
        .split('Future<bool> _prependOlderPage')
        .first;
    expect(backfill.contains('_prependOlderPage'), isTrue);
    expect(backfill.contains('getMessagesForSession'), isFalse);
    expect(window.contains('notifyListeners()'), isTrue);
  });

  test('older history pages backward from the window, not from 0', () {
    expect(window.contains('getMessagesBeforePosition'), isTrue);
    expect(window.contains('_prependOlderPage'), isTrue);
    expect(window.contains('loadOlderHistory'), isTrue);
    final older = window.split('Future<void> loadOlderHistory').last;
    expect(
      older.contains('_prependOlderPage'),
      isTrue,
      reason: 'scroll-up must fetch one older page, not await a full hydrate',
    );
    expect(older.contains('_awaitHistoryHydrated'), isFalse);
    expect(queries.contains('OrderingTerm.desc(m.position)'), isTrue);
  });
}
