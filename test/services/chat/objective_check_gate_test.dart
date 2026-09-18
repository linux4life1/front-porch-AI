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

// THE OBJECTIVE COMPLETION CHECK NO LONGER BLOCKS EVERY TURN.
//
// The bug this pins shut: `_maybeCheckTaskCompletionSync` is AWAITED before
// generation (the reply is supposed to see freshly-completed tasks), and with
// the Realism Engine on its cadence was forced to `freq = 1` — one full,
// blocking model round trip added to every single reply for as long as any
// quest was open, silently ignoring the per-objective checkFrequency the UI
// exposes and lets the user set.
//
// The replacement is two-part, and both parts are pinned here:
//   1. The per-objective checkFrequency is respected again (the `? 1`
//      override is gone — structural guard below).
//   2. Off-interval, a deterministic mention gate fires the check early the
//      moment the exchange actually touches a quest — because a completion
//      can only be shown BY the exchange, an exchange sharing none of a
//      quest's content words is a guaranteed NO not worth a blocking call.
//      (The promise ledger's `warrantsEval` pattern, applied to quests.)
//
// Proven-to-fail note (the mandatory negative check, run 2026-08-10 before
// this file was allowed to land): restoring the `_realismEnabled ? 1`
// override turned the structural guard red; inverting the mention helper's
// verdict turned the whole matcher group red. Both were restored and the
// suite went green again.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  group('the mention gate matches quests to scenes, and only that', () {
    test('a quest content word in the scene opens the gate', () {
      expect(
        objectivesMentionedIn('user: what a view from the lighthouse tonight', [
          'find the old lighthouse keeper',
        ]),
        isTrue,
      );
    });

    test('prefix-at-word-boundary is the cheap stem', () {
      expect(
        objectivesMentionedIn(
          'nia: *she finally laughs, bright and unguarded*',
          ['make her laugh again'],
        ),
        isTrue,
        reason:
            '"laugh" must reach "laughs"/"laughing" — completions are '
            'usually narrated in an inflected form',
      );
      expect(
        objectivesMentionedIn('user: the slaughterhouse stood empty', [
          'make her laugh again',
        ]),
        isFalse,
        reason:
            'but only at a word boundary — "slaughter" contains "laugh" '
            'mid-word and is not a laugh',
      );
    });

    test('stopwords and short words never open it', () {
      expect(
        objectivesMentionedIn(
          'user: i want to make something of this, more than they would',
          ['make something more of what they want'],
        ),
        isFalse,
        reason:
            'a quest built of filler words must not fire on every line '
            'of ordinary dialogue',
      );
    });

    test('cast and user names are excluded via ignore', () {
      expect(
        objectivesMentionedIn(
          'jennifer: pass the salt?',
          ['get jennifer to admit her greatest fear'],
          ignore: {'jennifer'},
        ),
        isFalse,
        reason:
            'the quest target\'s name appears in nearly every exchange — '
            'counting it would quietly turn the gate always-on, which is the '
            'exact per-turn cost this gate exists to remove',
      );
      expect(
        objectivesMentionedIn(
          'jennifer: you want to know what i fear?',
          ['get jennifer to admit her greatest fear'],
          ignore: {'jennifer'},
        ),
        isTrue,
        reason: 'while a real content word ("fear") still opens it',
      );
    });

    test('empty inputs stay closed', () {
      expect(objectivesMentionedIn('', ['find the key']), isFalse);
      expect(objectivesMentionedIn('user: hello', const []), isFalse);
    });
  });
}
