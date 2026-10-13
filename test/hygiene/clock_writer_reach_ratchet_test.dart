// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The story clock writer is public (it is a leaf class ChatService owns), so
// the barrel exports it. Only ChatService may drive it: a page or the web
// facade calling writeSlotClock would move the clock without ChatService's
// save and notify. clock_write_sites_ratchet_test pins where the writer
// writes; this pins who may reach it.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _owner = 'lib/services/chat/';

final _writerApi = RegExp(
  r'\b(StoryClockWriter|SlotClockWrite|writeSlotClock|clockWriteSlot|'
  r'pendingNudgeBefore|applyTipClock|applyDay1Clock|rewindLiveToSlotBefore)\b',
);

List<RatchetHit> _reachesOutside(String path, String source) =>
    path.startsWith(_owner)
    ? const []
    : DartSource(path, source).hits(_writerApi);

void main() {
  test('scanner self-test: a page calling the writer is caught, a comment '
      'naming it is not', () {
    const page = '''
// writeSlotClock is ChatService's.
void tap(StoryClockWriter w) => w.writeSlotClock(null);
''';
    expect(_reachesOutside('lib/ui/pages/x.dart', page), hasLength(2));
    expect(_reachesOutside('lib/services/chat/x.dart', page), isEmpty);
  });

  test('only lib/services/chat/ reaches the story clock writer', () {
    final hits = [
      for (final path in dartFiles('lib'))
        ..._reachesOutside(path, DartSource.read(path).source),
    ];
    expect(
      hits.map((h) => '${h.path}:${h.line} ${h.match}').toList(),
      isEmpty,
      reason:
          'The story clock is written only through ChatService. Call a '
          'ChatService method (which saves and notifies) instead.',
    );
  });
}
