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

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/search_injection.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';

void main() {
  test('empty-result fragment names the query and forbids invention', () {
    final text = webSearchEmptyResultFragment('Wandenreich');
    expect(text, contains('Wandenreich'));
    expect(text, contains('You do not know this'));
    expect(text, contains('Do not invent'));
    expect(text.toLowerCase(), isNot(contains('wiki')));
  });

  test('a successful snippet is a gated fragment, not a cited source', () {
    final text = webSearchResultFragment(
      'The Wandenreich is the Quincy empire.',
    );
    expect(text, contains('Quincy empire'));
    expect(text.toLowerCase(), isNot(contains('http')));
    expect(kWebSearchCharacterLine, contains('react to it as yourself'));
    expect(kWebSearchCharacterLine, contains("Don't break character"));
  });

  test('result fragment is facts, not a calendar, and forbids invention', () {
    final text = webSearchResultFragment(
      'Sunny, 72, light wind. Tuesday forecast.',
    );
    expect(text, contains('Sunny, 72'));
    expect(text.toLowerCase(), contains('do not invent'));
    expect(
      text.toLowerCase(),
      contains('not a calendar'),
      reason:
          'story clock is already in the prompt; a real-world as-of '
          'stamp collides with 1840 / 2077',
    );
    expect(text.toLowerCase(), contains('weekday'));
    expect(
      text.toLowerCase(),
      isNot(contains('today is')),
      reason: 'must not inject a real-world date or weekday',
    );
    expect(text, isNot(contains('2026')));
    expect(text, isNot(contains('September')));
  });

  test('web_search tool schema advertises query as the required param', () {
    expect(kWebSearchToolName, 'web_search');
    final tool = kWebSearchTools.single;
    expect(tool['type'], 'function');
    final fn = tool['function'] as Map;
    expect(fn['name'], 'web_search');
    expect(fn['description'], contains("do not recognize"));
    final params = fn['parameters'] as Map;
    expect(params['required'], ['query']);
  });

  test('decision cue tells the model to search unknown facts on its own', () {
    expect(kWebSearchDecisionCue, contains('web_search'));
    expect(kWebSearchDecisionCue.toLowerCase(), contains('weather'));
    expect(kWebSearchDecisionCue.toLowerCase(), contains('fiction'));
    expect(kWebSearchDecisionCue.toLowerCase(), contains('not your reply'));
    expect(kWebSearchDecisionCue.toLowerCase(), contains('do not guess'));
    expect(
      kWebSearchDecisionCue.toLowerCase(),
      contains('not breaking character'),
    );
    expect(
      kWebSearchDecisionCue.toLowerCase(),
      isNot(contains('real-world')),
      reason:
          'Gandalf / the Ring / anime must search too — '
          'do not gate on real-world facts',
    );
    expect(
      kWebSearchCharacterLine,
      contains('react to it as yourself'),
      reason: 'after-search in-character reaction must stay',
    );
  });

  test('decision prompt appends the cue after the RP tail', () {
    const tail = 'Iris:\n';
    final prompted = webSearchDecisionPrompt(tail);
    expect(prompted.startsWith(tail), isTrue);
    expect(prompted.endsWith(kWebSearchDecisionCue), isTrue);
    expect(
      prompted.indexOf(tail),
      lessThan(prompted.indexOf(kWebSearchDecisionCue)),
    );
  });

  test('decision system prompt keeps the standing line and adds the cue', () {
    final system = webSearchDecisionSystemPrompt(kWebSearchCharacterLine);
    expect(system, contains(kWebSearchCharacterLine));
    expect(system, contains(kWebSearchDecisionCue));
    expect(
      system.indexOf(kWebSearchCharacterLine),
      lessThan(system.indexOf(kWebSearchDecisionCue)),
    );
  });
}
