// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// After a web_search/MCP inject, the character completion point must still
// be the speaker prefix (`Name:`). PromptPlan insertion order IS render
// order; registering `web_search` after `suffix` left the untrusted dump
// as the last user-turn bytes the model continued from.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/prompt_injection/search_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_plan.dart';

void main() {
  test('after inject, userText still ends on the speaker prefix', () {
    final plan = PromptPlan()
      ..add(id: 'history', text: 'Sam: what is zxqwt\n')
      ..add(
        id: 'web_search',
        text: '${SearchInjection.emptyResultFragment('zxqwt')}\n',
      )
      ..add(id: 'suffix', text: '\nMara:')
      ..add(id: 'chance_time', text: '')
      ..add(id: 'porch_night', text: '')
      ..add(id: 'item_intro', text: '');

    expect(
      plan.userText.trimRight(),
      endsWith('Mara:'),
      reason: 'the model must complete the character line, not the dump',
    );
    expect(
      plan.userText.indexOf('zxqwt'),
      lessThan(plan.userText.lastIndexOf('Mara:')),
    );
  });
}
