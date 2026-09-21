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

// THE CLIMAX PASS MUST NOT INDEX INTO swipeMetadata BY HAND.
//
// `swipeMetadata` is persisted only when at least one entry is non-null
// (ChatMessage.toJson). So a message the user swiped four times without the
// engine ever stamping anything comes back from the database — or out of an
// imported package — with a ONE-element list and `swipeIndex` 3.
//
// The Afterglow pass then wrote `msg.swipeMetadata[msg.swipeIndex] = meta`
// and threw RangeError from inside the post-generation phase: the user saw a
// bogus "generation failed" banner, and pockets, posture and the realism
// re-stamp that run after it were all skipped for that turn.
//
// `activeMetadata=` pads the list first, which is why the pass now goes
// through it.
//
// Honest labelling: `_runClimaxPass` is private and only reachable from a full
// generation turn, so the behavioural half below pins the MESSAGE SHAPE that
// blew up (and shows the raw write still throwing on it), and the second group
// pins the call site. Read it as "the trap is real and the pass no longer
// steps in it", not "a live climax was simulated".

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Four alternatives, nothing ever stamped — then saved and reloaded.
  ChatMessage reloadedFourSwipeMessage() {
    final fresh = ChatMessage(
      text: 'A',
      sender: 'Misty',
      isUser: false,
      swipes: const ['A', 'B', 'C', 'D'],
      swipeIndex: 3,
    );
    return ChatMessage.fromJson(fresh.toJson());
  }

  group('the reloaded shape the raw write died on', () {
    test('a stamp-less four-swipe message reloads with a one-entry list', () {
      final msg = reloadedFourSwipeMessage();

      expect(msg.swipes, hasLength(4));
      expect(msg.swipeIndex, 3);
      expect(
        msg.swipeMetadata,
        hasLength(1),
        reason:
            'toJson omits swipe_metadata entirely when every entry is '
            'null, so the constructor rebuilds it as [metadata] — this '
            'mismatch is the whole bug',
      );
    });

    test('the raw indexed write still throws on it', () {
      final msg = reloadedFourSwipeMessage();

      expect(
        () => msg.swipeMetadata[msg.swipeIndex] = {'climax_triggered': true},
        throwsRangeError,
        reason: 'documents why the pass may never index this list by hand',
      );
    });

    test('the setter pads and lands the stamp on the active swipe', () {
      final msg = reloadedFourSwipeMessage();

      msg.activeMetadata = {'climax_triggered': true, 'pre_climax_arousal': 88};

      expect(msg.swipeMetadata, hasLength(4));
      expect(msg.activeMetadata?['climax_triggered'], isTrue);
      expect(msg.activeMetadata?['pre_climax_arousal'], 88);
      expect(
        msg.swipeMetadata[0],
        isNull,
        reason: 'padding must not put this turn\'s climax on other variants',
      );
    });
  });
}
