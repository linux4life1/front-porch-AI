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

// Afterglow depends on the Realism Engine. Full stop.
//
// THE BUG, as a user hit it: 18+ on, Realism Engine on, Afterglow on — and
// nothing ever happens. Arousal pins at 100 forever. The Porch Life row shows
// the switch live and ungreyed the whole time, because its one declared
// dependency is satisfied.
//
// The cooldown's only trigger is climax detection, and climax detection rode
// the needs-impact eval, which opens
//
//     if (!getNeedsSimEnabled() || !getRealismEnabled()) return;
//
// `CharacterCard.needsSimEnabled` DEFAULTS FALSE, so on most cards that eval
// never ran and Afterglow never started. A dependency nobody declared.
//
// TWO PROPERTIES ARE PINNED HERE, and the second exists because the first
// attempt at this fix got it wrong:
//
//   1. Climax does not route through Needs.
//   2. Climax runs POST-GENERATION. It reads the reply. An earlier draft moved
//      it onto the pre-generation arousal eval, which scores the USER's
//      message — it would have judged a reply that did not exist yet, lagged a
//      turn, re-fired on the same climax still in recent history, and put the
//      pre-gen judge in the business of scoring the character's own words,
//      which the settled rule forbids because a reroll would reroll it.
//      The full unit and golden suites were GREEN on that version. Nothing
//      tested when it ran. That is what the second group is for.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/climax_eval.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the check asks one question, and asks it well', () {
    test('the prompt carries the criteria, not just the question', () {
      final p = ClimaxEval.buildPrompt(
        charName: 'Jennifer',
        reply: 'she shuddered and went limp',
        recentExchange: '',
        toolsMode: false,
      );

      expect(p, contains('CLIMAX DETECTION'));
      expect(
        p,
        contains('are NOT a climax'),
        reason:
            'without explicit criteria a model — especially a reasoning '
            'one — almost never answers true, and the Lust bar stays pinned '
            'at the top forever',
      );
      expect(
        p,
        contains('she shuddered and went limp'),
        reason:
            'it judges the REPLY; a prompt without the reply in it is '
            'judging nothing',
      );
    });

    test('both fields are required in the tool schema', () {
      final params =
          ClimaxEval.tools.single['function']['parameters']
              as Map<String, dynamic>;

      expect(
        params['required'],
        containsAll(['is_climax', 'refractory_turns']),
        reason:
            'optional means never emitted — a model fills in what the '
            'schema demands and skips what it does not, which is how orgasm '
            'detection was silently off on every tools-capable backend once '
            'before',
      );
    });

    test('a true verdict yields the refractory, false yields nothing', () {
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true,"refractory_turns":6}'),
        6,
      );
      expect(
        ClimaxEval.parseRefractory('{"is_climax":false,"refractory_turns":0}'),
        isNull,
      );
    });

    test('a loose backend still gets read correctly', () {
      expect(
        ClimaxEval.parseRefractory(
          '{"is_climax":"true","refractory_turns":"4"}',
        ),
        4,
        reason: 'quoted values are the local-model floor',
      );
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true}'),
        5,
        reason:
            'a missing refractory must not discard a climax that WAS '
            'reported — fall back to the middle of the range',
      );
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true,"refractory_turns":99}'),
        10,
        reason: 'and it stays clamped',
      );
      expect(ClimaxEval.parseRefractory(null), isNull);
      expect(ClimaxEval.parseRefractory('nonsense'), isNull);
    });
  });

  test('the realism tools no longer carry it either', () {
    for (final tool in [
      kEmotionalEvalTools,
      kOneShotEvalTools,
      kNeedsImpactEvalTools,
    ]) {
      final params =
          tool.single['function']['parameters'] as Map<String, dynamic>;
      expect((params['properties'] as Map).containsKey('is_climax'), isFalse);
    }
  });
}
