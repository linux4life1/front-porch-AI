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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';

void main() {
  CharacterCard tsundere() => CharacterCard(
    name: 'Mira',
    description: 'A sharp-tongued engineer who pretends not to care.',
    personality: 'tsundere, dry, teases then does the work anyway',
    scenario: 'SCENARIO_MUST_NOT_APPEAR — a rainy porch date, not the job',
    firstMessage: 'FIRST_MESSAGE_MUST_NOT_APPEAR',
    mesExample:
        '{{char}}: Hmph. Fine. I will look at the test.\n{{user}}: thanks',
    systemPrompt: 'You speak in short, pointed sentences.',
    frontPorchExtensions: FrontPorchExtensions(
      occupation: 'OCCUPATION_MUST_NOT_APPEAR',
    ),
  );

  test('prompt includes card identity and the Desk preamble', () {
    final prompt = buildDeskCoworkerPrompt(tsundere());
    expect(prompt, contains('Mira'));
    expect(prompt, contains('sharp-tongued engineer'));
    expect(prompt, contains('tsundere'));
    expect(prompt, contains('You speak in short, pointed sentences.'));
    expect(prompt, contains(kDeskPreamble));
    expect(prompt, contains('Hmph. Fine.'));
  });

  test('prompt excludes scenario, greeting, and Porch Life extensions', () {
    final prompt = buildDeskCoworkerPrompt(tsundere());
    expect(prompt, isNot(contains('SCENARIO_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('FIRST_MESSAGE_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('OCCUPATION_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('rainy porch date')));
  });

  test('empty systemPrompt is omitted rather than injected as blank noise', () {
    final card = CharacterCard(
      name: 'Ada',
      personality: 'calm',
      systemPrompt: '   ',
    );
    final prompt = buildDeskCoworkerPrompt(card);
    expect(prompt, contains('Ada'));
    expect(prompt, contains('calm'));
    expect(prompt, isNot(contains('System prompt:')));
  });
}
