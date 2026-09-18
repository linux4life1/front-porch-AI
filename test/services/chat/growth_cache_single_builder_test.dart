// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// ONE BUILDER FOR THE GROWTH INJECTION CACHE.
//
// `GrowthStore.refresh(sessionId, charIds: …)` clears the cache and refills it
// with ONLY the ids it is handed, then marks it valid. Hand it a short list and
// everyone missing from it reads back as "no rings" — silently, because a valid
// empty cache looks exactly like a character who has not grown yet.
//
// The timeline-integrity path (`_invalidateGrowthFrom`, reached from every
// regen / edit / delete / swipe that purges a ring) had its OWN hand-rolled id
// list. It listed the active character and the group members and forgot Scene
// Guests — so a guest's growth rings vanished from the injection until the chat
// was reloaded. `_refreshGrowthCache` is the canonical builder and does include
// them; the copy is gone.
//
// Honest labelling: this is STRUCTURAL. Populating `_sceneGuest.cards` needs a
// full guest-entrance turn against a live model, so there is no cheap
// behavioural seam. Read it as "there is exactly one place that decides who is
// in the cache, and it knows about guests" — which is the invariant that broke.
// Same shape as the "applyClimaxEffects has exactly one caller" pin in
// afterglow_independence_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String read(String name) =>
      File('lib/services/chat/$name').readAsStringSync();

  test('only one place in lib/ calls GrowthStore.refresh', () {
    final callers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('_growthStore.refresh('))
        .map((f) => f.path)
        .toList();

    expect(
      callers,
      hasLength(1),
      reason:
          'a second call site is a second roster, and the second roster '
          'is how Scene Guests got dropped: $callers',
    );
    expect(callers.single, contains('chat_service_growth.dart'));
  });

  test('the one builder counts Scene Guests', () {
    final builder = read('chat_service_growth.dart');
    final start = builder.indexOf('Future<void> _refreshGrowthCache()');
    expect(start, greaterThan(-1));
    final body = builder.substring(
      start,
      builder.indexOf('_growthStore.refresh(', start),
    );

    expect(
      body,
      contains('_sceneGuest.cards'),
      reason:
          'guests are cast members with their own rings — leaving them '
          'out of the id list empties their growth from the injection',
    );
  });

  test('timeline invalidation rebuilds through that builder', () {
    expect(
      read('chat_service_timeline.dart'),
      contains('await _refreshGrowthCache();'),
      reason:
          'after purging rings the cache must be rebuilt by the canonical '
          'builder, not by a local copy of its id list',
    );
  });
}
