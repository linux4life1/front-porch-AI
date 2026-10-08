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

// Pixel goldens for the AI creator's Greetings step (#370), seeded with the
// approved sketch's own text: the step at rest (a steer typed on alternate 1),
// the step while alternate 1 is being written (Stop, the rest waiting), and
// the Realism step's outfit hint. Light + dark each.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/steps/greetings_step.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';

import '../support/creator_test_support.dart';
import '../support/golden_app.dart';

const _first =
    "*The lamp room hums as the beam sweeps the water. {{char}} doesn't look "
    'up from the logbook when the hatch creaks open.* "Third boat this week '
    "to lose its way. Sit by the stove. The tea's still hot, and you look "
    'like you\'ve been arguing with the tide."';
const _alt1 =
    '*Rain hammers the gallery rail. {{char}} hauls you over the last rung by '
    'the collar of your coat.* "Inside, before the wind takes you. Whatever '
    'you\'re running from can wait until you\'ve stopped shaking."';
const _alt2 =
    '*Fog lies flat over the harbor. {{char}} is mending a net on the jetty '
    'and nods at the empty crate beside her.* "Market boat\'s late again. '
    "Make yourself useful while we wait, or tell me why you're out here "
    'before sunrise."';

CreatorState _seed() {
  final state = CreatorState();
  state.generatedCard = CharacterCard(
    name: 'Aria Vale',
    firstMessage: _first,
    alternateGreetings: const [_alt1, _alt2],
  );
  state.firstMessageController = state.newGreetingBox(_first);
  state.altGreetingControllers = [
    state.newGreetingBox(_alt1),
    state.newGreetingBox(_alt2),
  ];
  state.greetings.steerFor(state.altGreetingControllers[0]).text =
      'make it a calm morning instead';
  return state;
}

Widget _step(CreatorState state) =>
    SizedBox(width: 900, height: 1160, child: GreetingsStep(state: state));

void main() {
  setupPathProviderMock();

  testWidgets('GreetingsStep — at rest, a steer typed', (tester) async {
    final state = _seed();
    addTearDown(state.dispose);
    await expectThemedGoldens(
      tester,
      child: _step(state),
      group: 'creator_greetings',
      name: 'step',
      surface: const Size(940, 1200),
      settle: false,
    );
  });

  testWidgets('GreetingsStep — alternate 1 being written', (tester) async {
    final state = _seed();
    addTearDown(state.dispose);
    state.greetings
      ..writingIndex = 1
      ..writingText =
          '*Morning light spills across the market square. {{char}} is '
          'haggling over a crate of lamp oil and waves you over without '
          'looking.* "You there. Tell this man';
    await expectThemedGoldens(
      tester,
      child: _step(state),
      group: 'creator_greetings',
      name: 'writing',
      surface: const Size(940, 1200),
      settle: false,
    );
  });

  testWidgets('OutfitHint — the first message changed', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 852,
        child: OutfitHint(reading: false, onReread: () {}, onKeep: () {}),
      ),
      group: 'creator_greetings',
      name: 'outfit_hint',
      surface: const Size(900, 200),
    );
  });
}
