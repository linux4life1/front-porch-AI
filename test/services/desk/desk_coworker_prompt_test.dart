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

  test('persona sits on top of the coding preamble', () {
    final now = DateTime(2026, 9, 6);
    final prompt = buildDeskCoworkerPrompt(tsundere(), now: now);
    expect(prompt.indexOf('Name: Mira'), 0);
    expect(
      prompt,
      contains('Persona: tsundere, dry, teases then does the work anyway'),
    );
    expect(
      prompt.indexOf('Name: Mira'),
      lessThan(prompt.indexOf(kDeskPreamble)),
    );
    expect(prompt.indexOf('Persona:'), lessThan(prompt.indexOf(kDeskPreamble)));
    expect(prompt, contains('Today: 2026-09-06'));
    expect(prompt, contains(kDeskPreamble));
    expect(prompt, contains('Never paste full source files into the chat'));
    expect(prompt, contains('Training cutoff is not evidence'));
  });

  test('talk samples expand macros and stay out of the scene', () {
    final prompt = buildDeskCoworkerPrompt(tsundere());
    expect(prompt, contains('Mira: Hmph. Fine. I will look at the test.'));
    expect(prompt, contains('User: thanks'));
    expect(prompt, contains('diction only'));
    expect(prompt, isNot(contains('{{char}}')));
  });

  test('chat systemPrompt, scenario, greeting, and description stay out', () {
    final prompt = buildDeskCoworkerPrompt(tsundere());
    expect(prompt, isNot(contains('You speak in short, pointed sentences.')));
    expect(prompt, isNot(contains('System prompt:')));
    expect(prompt, isNot(contains('SCENARIO_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('FIRST_MESSAGE_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('OCCUPATION_MUST_NOT_APPEAR')));
    expect(prompt, isNot(contains('rainy porch date')));
    expect(prompt, isNot(contains('sharp-tongued engineer')));
  });

  test('preamble does not assume gender', () {
    expect(
      RegExp(r'\bshe\b', caseSensitive: false).hasMatch(kDeskPreamble),
      isFalse,
    );
    expect(
      RegExp(r'\bher\b', caseSensitive: false).hasMatch(kDeskPreamble),
      isFalse,
    );
    expect(
      RegExp(r'\bhers\b', caseSensitive: false).hasMatch(kDeskPreamble),
      isFalse,
    );
  });

  test('empty personality falls back to a clipped description', () {
    final card = CharacterCard(
      name: 'Ada',
      description: 'calm, precise, hates wasted motion',
      systemPrompt: 'CHAT_SYSTEM_MUST_NOT_APPEAR',
    );
    final prompt = buildDeskCoworkerPrompt(card);
    expect(prompt, contains('Persona: calm, precise, hates wasted motion'));
    expect(prompt, isNot(contains('CHAT_SYSTEM_MUST_NOT_APPEAR')));
  });

  test('talk samples cap at two chunks and 400 tokens', () {
    final a = 'A' * 200;
    final b = 'B' * 200;
    final c = 'C' * 200;
    final huge = 'D' * 5000;
    final feel = deskTalkFeel('$a\n\n$b\n\n$c', 'Mira');
    expect(feel, isNotNull);
    expect(feel, contains('A'));
    expect(feel, contains('B'));
    expect(feel, isNot(contains('C')));
    final clipped = deskTalkFeel(huge, 'Mira')!;
    expect(
      deskEstimateTokens(clipped),
      lessThanOrEqualTo(kDeskTalkSampleMaxTokens),
    );
  });
}
