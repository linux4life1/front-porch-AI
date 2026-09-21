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

// A time the model only THOUGHT is not a time the character said.
//
// clockNamedInReply reads a spoken clock out of a reply and moves the story
// clock's displayed time to match. Reasoning is not speech: the think block
// quotes the injected "It is currently …" line back at itself, so mining it
// for claims lets the prompt set the clock instead of the fiction.
//
// It stripped CLOSED blocks only, with a local regex. An unclosed `<think>` —
// a cut-off stream, the single most common shape in this codebase's bug
// reports — sailed straight through, reasoning and all. It now uses the shared
// stripThinkTags, which also drops an unclosed tail and a bare orphan closer.
//
// Proven red: restore the old closed-only regex and the unclosed case below
// returns 15:15, because "3:15 pm" inside the abandoned thought is read as
// something the character said out loud.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart' show clockNamedInReply;

void main() {
  final now = DateTime(2026, 9, 18, 14, 0);

  /// Hour and minute only: the helper builds its instant off the story clock
  /// it is handed, so comparing whole DateTimes would pin UTC-vs-local rather
  /// than the claim.
  void expectClaim(DateTime? got, int hour, int minute) {
    expect(got, isNotNull);
    expect([got!.hour, got.minute], [hour, minute]);
  }

  test('a time said out loud is honored', () {
    expectClaim(
      clockNamedInReply(
        '"It is 3:15 pm," she says, checking the hall clock.',
        now,
      ),
      15,
      15,
    );
  });

  test('a time inside a closed think block is not a claim', () {
    expect(
      clockNamedInReply(
        '<think>The prompt says it is 3:15 pm.</think>She pours the coffee.',
        now,
      ),
      isNull,
    );
  });

  test('a time inside an UNCLOSED think block is not a claim either', () {
    expect(
      clockNamedInReply(
        'She pours the coffee.\n<think>Hold on, it is 3:15 pm, so I should',
        now,
      ),
      isNull,
      reason:
          'a cut-off thought is still a thought; reading it lets the injected '
          'clock line set the clock',
    );
  });

  test('an orphan closing tag does not hide a real claim', () {
    expectClaim(
      clockNamedInReply('</think>"It is 3:15 pm," she says.', now),
      15,
      15,
    );
  });
}
