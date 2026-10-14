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

// Pixel goldens for the AI creator's Profile step (#530), seeded with the
// approved sketch's kind of text: the step at rest, the profile rewrite
// streaming into Description while Personality waits, the facts card
// dimmed during a re-read, the Greetings step's "The profile changed" hint,
// and a Review rewrite card. Light + dark each.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';

import '../support/creator_test_support.dart';
import '../support/golden_app.dart';

const _desc =
    '{{char}} is tall and weathered, with salt-grey braids and a coat that '
    'smells of lamp oil. Her hands are cracked from the winter rails.';
const _pers =
    '*Dry, patient, slow to warm.* She says "Sit by the stove" instead of '
    'hello, and never leaves a lamp unlit.';
const _scen = '{{user}} climbs the tower stairs at dusk, soaked through.';
const _transcript =
    'Q: What do you do all day?\nA: I keep the light.\n\n'
    'Q: What do you want most?\nA: One quiet winter.';

CreatorState _seed() {
  final state = CreatorState();
  final card = CharacterCard(
    name: 'Aria Vale',
    description: _desc,
    personality: _pers,
    scenario: _scen,
    creatorNotes: 'A keeper who outlasts every storm.',
  );
  state.generatedCard = card;
  state.ageController.text = '34';
  state.profile
    ..paused = GenPausedRun(
      inputs: const GenRunInputs(name: 'Aria Vale', concept: 'A keeper.'),
      card: card,
      interviewTranscript: _transcript,
    )
    ..facts = const IdentityFacts(warmth: 'strangers');
  state.adoptProfileBoxes(_desc, _pers, _scen);
  state
    ..realismBirthday = '1991-03-14'
    ..realismOccupation = 'lighthouse keeper'
    ..realismHours = '6pm–6am'
    ..realismWorkDays = const [1, 2, 3, 4, 5]
    ..realismCurrentTask = 'Trim the lamp before the storm.'
    ..realismAmbitions = const ['one quiet winter']
    ..realismLikes = const ['salt wind', 'strong tea']
    ..realismDislikes = const ['fog horns'];
  return state;
}

Widget _sized(Widget child, {double height = 2200}) =>
    SizedBox(width: 900, height: height, child: child);

void main() {
  setupPathProviderMock();

  testWidgets('ProfileStep — at rest', (tester) async {
    final state = _seed();
    addTearDown(state.dispose);
    await expectThemedGoldens(
      tester,
      child: _sized(ProfileStep(state: state)),
      group: 'creator_profile',
      name: 'step',
      surface: const Size(940, 2240),
      settle: false,
    );
  });

  testWidgets('ProfileStep — the rewrite streaming', (tester) async {
    final state = _seed();
    addTearDown(state.dispose);
    state.profile
      ..rewriting = true
      ..stream = parseProfileStream(
        '{"description": "{{char}} is tall and storm-worn, braids gone '
        'white at the',
      );
    state.profile.steer.text = 'Does not follow the Tsundere personality type';
    await expectThemedGoldens(
      tester,
      child: _sized(ProfileStep(state: state)),
      group: 'creator_profile',
      name: 'writing',
      surface: const Size(940, 2240),
      settle: false,
    );
  });

  testWidgets('ProfileStep — the facts card during a re-read', (tester) async {
    final state = _seed();
    addTearDown(state.dispose);
    state.profile.rereadingFacts = true;
    await expectThemedGoldens(
      tester,
      child: _sized(ProfileStep(state: state)),
      group: 'creator_profile',
      name: 'facts_dimmed',
      surface: const Size(940, 2240),
      settle: false,
    );
  });

  testWidgets('ProfileHint — the profile changed', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 852,
        child: ProfileHint(rewriting: false, onRewrite: () {}, onKeep: () {}),
      ),
      group: 'creator_profile',
      name: 'hint',
      surface: const Size(900, 200),
    );
  });

  testWidgets('ReviewRewriteRow — the example dialogue', (tester) async {
    final steer = TextEditingController(text: 'shorter lines, more bite');
    addTearDown(steer.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 852,
        child: ReviewRewriteRow(
          id: 'review-dialogue',
          steer: steer,
          hint: 'Steer it (optional), e.g. shorter lines, more bite',
          action: 'Regenerate',
          writing: false,
          onRun: () {},
          onStop: () {},
        ),
      ),
      group: 'creator_profile',
      name: 'review_rewrite',
      surface: const Size(900, 120),
    );
  });
}
