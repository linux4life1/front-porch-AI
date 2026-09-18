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

// THE [EvalTraffic] LINE IS THE EVAL SYSTEM'S ODOMETER.
//
// The eval review's own sequencing said "instrument first": the state-zone
// placement won its argument with a measured number, and the eval-side
// optimizations (fusion, shared prefix, the quest-check gate, one-shot Auto)
// deserve the same footing. This tally is that footing — every secondary
// call recorded at the transport chokepoints, one summary line per turn,
// one `background` line for what the fire-and-forget passes spent between
// turns.
//
// Pinned here: the tally arithmetic and flush semantics (pure), and — the
// part a green unit suite cannot see — that the chokepoints actually record
// and the turn actually prints (structural, like the placement guards next
// door). A counter that silently stops counting reads as "the optimization
// still holds" while calls pile back up; that failure mode is exactly why
// the structural group exists.
//
// Proven-to-fail note (the mandatory negative check, run 2026-08-10 before
// this file was allowed to land): making record() drop entries turned the
// arithmetic group red; removing the engine's record call turned the
// chokepoint guard red. Both were restored and the suite went green again.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  // The static instance is shared; every test starts from a drained tally.
  setUp(EvalTraffic.current.flushTurn);

  group('the tally arithmetic', () {
    test('one turn line: counts, totals, estimate, per-call detail', () {
      EvalTraffic.current.record(
        label: 'realism',
        lane: 'text',
        promptChars: 6000,
        outputChars: 120,
        ms: 1500,
      );
      EvalTraffic.current.record(
        label: 'reply_facts',
        lane: 'tools',
        promptChars: 2000,
        outputChars: 80,
        ms: 500,
      );

      final line = EvalTraffic.current.flushTurn();
      expect(line, isNotNull);
      expect(line, startsWith('[EvalTraffic] 2 calls'));
      expect(line, contains('8.0k prompt chars'));
      expect(
        line,
        contains('≈2.0k tok'),
        reason: 'the token figure is chars ÷ 4 and must say so as an estimate',
      );
      expect(line, contains('2.00s LLM time'));
      expect(line, contains('realism(text) 6.0k→120 1.50s'));
      expect(line, contains('reply_facts(tools) 2.0k→80 0.50s'));
    });

    test('flushing clears — the same spend is never reported twice', () {
      EvalTraffic.current.record(
        label: 'x',
        lane: 'text',
        promptChars: 10,
        outputChars: 1,
        ms: 1,
      );
      expect(EvalTraffic.current.flushTurn(), isNotNull);
      expect(
        EvalTraffic.current.flushTurn(),
        isNull,
        reason: 'in a group every speaker prints a delta, not a running total',
      );
    });

    test('a quiet tally prints nothing at all', () {
      expect(EvalTraffic.current.flushTurn(), isNull);
      expect(EvalTraffic.current.flushBackground(), isNull);
    });

    test('the background flush names itself', () {
      EvalTraffic.current.record(
        label: 'journal',
        lane: 'tools',
        promptChars: 9000,
        outputChars: 700,
        ms: 4000,
      );
      expect(
        EvalTraffic.current.flushBackground(),
        contains('[EvalTraffic] background 1 call'),
        reason:
            'spend from the fire-and-forget passes must not read as part '
            'of the turn the user just waited for',
      );
    });
  });
}
