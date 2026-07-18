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

// Widget pixel goldens for the 5 remaining AI Character Creator wizard screens
// not covered by creator_steps_golden_test.dart (ModeSelect, QuickConfig,
// Realism, Review).
//
// Screens covered:
//   SetupStep            — openRouter backend. LLMProvider is read at build
//                          time (line 32 of setup_step.dart); the kobold
//                          branch is skipped when
//                          activeBackend == BackendType.openRouter, so only
//                          FakeLLMProvider is needed.
//   GuidedConfigStep     — seeded CreatorState (guided mode). The sub-widget
//                          GuidedOutputSettings embeds PersonaSelectorDropdown
//                          which calls Provider.of<UserPersonaService> at
//                          build time → FakeUserPersonaService required.
//                          All LLMProvider/StorageService reads in this step
//                          are inside async callbacks, not build().
//   GuidedOutputSettings — seeded state; same PersonaSelectorDropdown →
//                          FakeUserPersonaService.
//   AutomatedConfigStep  — seeded state; PersonaSelectorDropdown at line 220 →
//                          FakeUserPersonaService. LLMProvider/StorageService
//                          reads are in the name-randomize callback only.
//   GeneratingStep       — seeded state with status + progress; no providers;
//                          AnimationController.repeat() → settle: false.
//
// Light + dark for each (10 PNGs total).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/steps/automated_config_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/generating_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/guided_config_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/guided_output_settings.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

CreatorState _seedState() {
  final state = CreatorState();
  state.creatorMode = CreatorMode.guided;
  state.nameController.text = 'Aria Vale';
  state.conceptController.text =
      'A lighthouse keeper who collects shipwreck tales.';
  state.realismStepEnabled = true;
  state.realismNeedsSim = true;
  state.generationStatus = 'Writing personality...';
  state.progress = 0.4;

  final card = CharacterCard(
    name: 'Aria Vale',
    description: '{{char}} is a lighthouse keeper on a wind-scoured cape.',
    personality: 'Patient, observant, dry-humored.',
    scenario: '{{user}} climbs the tower stairs at dusk.',
    firstMessage: 'The lamp turns. "You came, {{user}}."',
    lorebook: Lorebook(entries: [
      LorebookEntry(key: 'lighthouse', content: 'The lamp never goes dark.'),
      LorebookEntry(key: 'storm', content: 'A wreck washed in last winter.'),
    ]),
  );
  state.generatedCard = card;
  state.descController.text = card.description;
  state.personalityController.text = card.personality;
  state.scenarioController.text = card.scenario;
  state.firstMessageController.text = card.firstMessage;
  state.lorebookEntryEnabled = {0: true, 1: true};
  return state;
}

void main() {
  setupPathProviderMock();

  testWidgets('SetupStep — openRouter backend (remote model section)',
      (tester) async {
    final llm = FakeLLMProvider(activeBackend: BackendType.openRouter);
    addTearDown(llm.dispose);
    final state = _seedState();
    addTearDown(state.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<LLMProvider>.value(
        value: llm,
        child: SizedBox(
          width: 860,
          height: 720,
          child: SingleChildScrollView(child: SetupStep(state: state)),
        ),
      ),
      group: 'creator_steps_remaining',
      name: 'setup',
      surface: const Size(900, 760),
    );
  });

  testWidgets('GuidedConfigStep — seeded guided-mode state', (tester) async {
    final personas = FakeUserPersonaService();
    addTearDown(personas.dispose);
    final state = _seedState();
    addTearDown(state.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: SizedBox(
          width: 760,
          height: 1100,
          child: SingleChildScrollView(child: GuidedConfigStep(state: state)),
        ),
      ),
      group: 'creator_steps_remaining',
      name: 'guided_config',
      surface: const Size(800, 1140),
      // StyledTextControllers inside sub-fields create cursor tickers.
      settle: false,
    );
  });

  testWidgets('GuidedOutputSettings — seeded state, empty persona list',
      (tester) async {
    final personas = FakeUserPersonaService();
    addTearDown(personas.dispose);
    final state = _seedState();
    addTearDown(state.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: SizedBox(
          width: 760,
          height: 700,
          child: SingleChildScrollView(
            child: GuidedOutputSettings(state: state),
          ),
        ),
      ),
      group: 'creator_steps_remaining',
      name: 'guided_output_settings',
      surface: const Size(800, 740),
    );
  });

  testWidgets('AutomatedConfigStep — seeded state, empty persona list',
      (tester) async {
    final personas = FakeUserPersonaService();
    addTearDown(personas.dispose);
    final state = _seedState();
    addTearDown(state.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: SizedBox(
          width: 760,
          height: 1100,
          child: SingleChildScrollView(
            child: AutomatedConfigStep(state: state),
          ),
        ),
      ),
      group: 'creator_steps_remaining',
      name: 'automated_config',
      surface: const Size(800, 1140),
      // TextEditingControllers create cursor tickers.
      settle: false,
    );
  });

  testWidgets('GeneratingStep — 40% progress, status label', (tester) async {
    final state = _seedState();
    addTearDown(state.dispose);

    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 700,
        height: 480,
        child: GeneratingStep(state: state),
      ),
      group: 'creator_steps_remaining',
      name: 'generating',
      surface: const Size(740, 520),
      // AnimationController.repeat() never settles.
      settle: false,
    );
  });
}
