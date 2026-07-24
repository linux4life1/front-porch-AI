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

@Tags(['golden'])
@TestOn('linux')
library;

// Widget pixel goldens for steps 1–5 of CreateCharacterPage (manual creator).
// Step 0 (Identity) is already covered in pages_golden_test.dart. Step 6
// (Portrait & Avatars, phase #12) is deliberately NOT goldened here: it only
// renders after a real save (repository + storage + image-gen providers), so
// its layout is locked by the AI creator's review golden hosting the same
// shared AvatarGenerationPanel instead.
//
// Navigation strategy: each test pumps the full CreateCharacterPage, then
// uses afterPump to:
//   1. Enter 'Aria Vale' in the name TextFormField (required by step 0→1
//      validation before _currentStep advances).
//   2. Tap "Next: <label>" buttons in sequence until the target step.
//   3. Pump 350ms after each tap to clear the 300ms AnimatedSwitcher
//      transition.
// afterPump runs once per theme (light + dark), so navigation repeats
// cleanly for each capture.
//
// Provider tree: none needed — all Provider.of calls in CreateCharacterPage
// are inside onPressed callbacks and _createAndAdvance(); never at build time.
//
// All tests use settle: false — StyledTextControllers create debounce Timers
// and cursor tickers that prevent pumpAndSettle from returning.
//
// Steps covered:
//   1 — Personality (description, personality, scenario, advanced prompts)
//   2 — Dialogue   (first message, alt greetings, example dialogues)
//   3 — Lorebook   (empty list → "no entries" empty state)
//   4 — Realism Engine (initial-state form)
//   5 — Review & Create (character summary + create button)
//
// Light + dark for each (10 PNGs total).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/create_character_page.dart';

import '../support/creator_test_support.dart';
import '../support/golden_app.dart';

/// Navigate [CreateCharacterPage] from step 0 to [targetStep] by entering the
/// required name and tapping "Next: …" buttons in order.
Future<void> _navigateTo(WidgetTester tester, int targetStep) async {
  const labels = [
    'Personality',
    'Dialogue',
    'Lorebook',
    'Realism Engine',
    'Review & Create',
  ];
  // Enter name — required for the step 0 → 1 guard check.
  await tester.enterText(find.byType(TextFormField).first, 'Aria Vale');
  await tester.pump();
  for (var i = 0; i < targetStep; i++) {
    await tester.tap(find.text('Next: ${labels[i]}'));
    // Pump past the 300ms AnimatedSwitcher cross-fade animation.
    await tester.pump(const Duration(milliseconds: 350));
  }
}

void main() {
  setupPathProviderMock();

  testWidgets('CreateCharacterPage — step 1 Personality', (tester) async {
    await expectThemedGoldens(
      tester,
      // UniqueKey() forces a fresh State on each pumpWidget call so
      // _currentStep resets to 0 between the light and dark passes.
      childBuilder: () => CreateCharacterPage(key: UniqueKey()),
      group: 'manual_creator',
      name: 'step_1_personality',
      surface: const Size(1280, 900),
      settle: false,
      afterPump: (tester) => _navigateTo(tester, 1),
    );
  });

  testWidgets('CreateCharacterPage — step 2 Dialogue', (tester) async {
    await expectThemedGoldens(
      tester,
      childBuilder: () => CreateCharacterPage(key: UniqueKey()),
      group: 'manual_creator',
      name: 'step_2_dialogue',
      surface: const Size(1280, 900),
      settle: false,
      afterPump: (tester) => _navigateTo(tester, 2),
    );
  });

  testWidgets('CreateCharacterPage — step 3 Lorebook', (tester) async {
    await expectThemedGoldens(
      tester,
      childBuilder: () => CreateCharacterPage(key: UniqueKey()),
      group: 'manual_creator',
      name: 'step_3_lorebook',
      surface: const Size(1280, 900),
      settle: false,
      afterPump: (tester) => _navigateTo(tester, 3),
    );
  });

  testWidgets('CreateCharacterPage — step 4 Realism Engine', (tester) async {
    await expectThemedGoldens(
      tester,
      childBuilder: () => CreateCharacterPage(key: UniqueKey()),
      group: 'manual_creator',
      name: 'step_4_realism',
      surface: const Size(1280, 900),
      settle: false,
      afterPump: (tester) => _navigateTo(tester, 4),
    );
  });

  testWidgets('CreateCharacterPage — step 5 Review & Create', (tester) async {
    await expectThemedGoldens(
      tester,
      childBuilder: () => CreateCharacterPage(key: UniqueKey()),
      group: 'manual_creator',
      name: 'step_5_review',
      surface: const Size(1280, 900),
      settle: false,
      afterPump: (tester) => _navigateTo(tester, 5),
    );
  });
}
