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

// Widget pixel goldens for the 10 remaining feasible leaf widgets in
// lib/ui/widgets/ not covered by leaf_widgets_golden_test.dart.
//
// Widgets covered (10 × 2 = 20 PNGs):
//   AppTextField              — label + hint text, no autofocus
//   CharacterNameInput        — seeded name 'Aria Vale' + randomize button
//   AgeGenderRow              — seeded age '25' + gender 'Female'
//   PersonaSelectorDropdown   — empty persona list via FakeUserPersonaService
//   ModelSelector             — empty model list (emptyMessage shown)
//   GreetingToneSelector      — 2 tones selected, 3 greetings, NSFW disabled
//   AvatarArtStyleSelector    — 'Anime' selected
//   FirstMessageLengthDropdown— 'Medium (2-4 paragraphs)' selected
//   AlternateGreetingsSlider  — value=3 with accent colour
//   DescriptionDetailChipRow  — 'Standard' selected
//
// Not feasible:
//   KcppsSelector   — StatefulWidget with FilePicker platform channel calls
//                     in initState/didUpdateWidget; not safely pumpable without
//                     a real platform channel stub.
//
// settle: false for the three TextField-bearing widgets so that any internal
// cursor tickers don't block pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/widgets/age_gender_row.dart';
import 'package:front_porch_ai/ui/widgets/alternate_greetings_slider.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/avatar_art_style_selector.dart';
import 'package:front_porch_ai/ui/widgets/character_name_input.dart';
import 'package:front_porch_ai/ui/widgets/description_detail_chip_row.dart';
import 'package:front_porch_ai/ui/widgets/first_message_length_dropdown.dart';
import 'package:front_porch_ai/ui/widgets/greeting_tone_selector.dart';
import 'package:front_porch_ai/ui/widgets/model_selector.dart';
import 'package:front_porch_ai/ui/widgets/persona_selector_dropdown.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

void main() {
  setupPathProviderMock();

  testWidgets('AppTextField — label + hint, no controller', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 360,
        child: AppTextField(
          decoration: const InputDecoration(
            labelText: 'Character Name',
            hintText: 'e.g. Aria Blackwood…',
          ),
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'app_text_field',
      surface: const Size(420, 100),
      // TextField cursor ticker fires when focused; guard against pumpAndSettle
      // hanging if Flutter focuses the field automatically on pump.
      settle: false,
    );
  });

  testWidgets('CharacterNameInput — seeded name + randomize button',
      (tester) async {
    final controller = TextEditingController(text: 'Aria Vale');
    addTearDown(controller.dispose);

    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 400,
        child: CharacterNameInput(
          controller: controller,
          onRandomize: () {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'character_name_input',
      surface: const Size(460, 140),
      settle: false,
    );
  });

  testWidgets('AgeGenderRow — seeded age + gender', (tester) async {
    final ageCtrl = TextEditingController(text: '25');
    final genderCtrl = TextEditingController(text: 'Female');
    addTearDown(() {
      ageCtrl.dispose();
      genderCtrl.dispose();
    });

    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 460,
        child: AgeGenderRow(
          ageController: ageCtrl,
          genderController: genderCtrl,
          onChanged: () {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'age_gender_row',
      surface: const Size(520, 110),
      settle: false,
    );
  });

  testWidgets('PersonaSelectorDropdown — empty persona list', (tester) async {
    final personas = FakeUserPersonaService();
    addTearDown(personas.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: SizedBox(
          width: 360,
          child: PersonaSelectorDropdown(
            selectedPersonaId: '',
            onChanged: (_) {},
          ),
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'persona_selector_dropdown',
      surface: const Size(420, 90),
    );
  });

  testWidgets('ModelSelector — empty model list', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 400,
        child: ModelSelector(
          models: const [],
          selectedModelPath: null,
          onChanged: (_) {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'model_selector',
      surface: const Size(460, 90),
    );
  });

  testWidgets('GreetingToneSelector — 2 tones, 3 greetings, NSFW off',
      (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 580,
        child: GreetingToneSelector(
          selectedTones: const ['Romantic', 'Wholesome'],
          greetingCount: 3,
          nsfwEnabled: false,
          accentColor: Colors.deepPurpleAccent,
          onChanged: (_) {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'greeting_tone_selector',
      surface: const Size(640, 240),
    );
  });

  testWidgets('AvatarArtStyleSelector — Anime selected', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 500,
        child: AvatarArtStyleSelector(
          selectedStyle: 'Anime',
          accentColor: Colors.deepPurpleAccent,
          onChanged: (_) {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'avatar_art_style_selector',
      surface: const Size(560, 200),
    );
  });

  testWidgets('FirstMessageLengthDropdown — Medium selected', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 380,
        child: FirstMessageLengthDropdown(
          value: 'Medium (2-4 paragraphs)',
          onChanged: (_) {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'first_message_length_dropdown',
      surface: const Size(440, 90),
    );
  });

  testWidgets('AlternateGreetingsSlider — value 3', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 420,
        child: AlternateGreetingsSlider(
          value: 3,
          accentColor: Colors.deepPurpleAccent,
          onChanged: (_) {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'alternate_greetings_slider',
      surface: const Size(480, 110),
    );
  });

  testWidgets('DescriptionDetailChipRow — Standard selected', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 460,
        child: DescriptionDetailChipRow(
          selectedDetail: 'Standard',
          onChanged: (_) {},
        ),
      ),
      group: 'leaf_widgets_remaining',
      name: 'description_detail_chip_row',
      surface: const Size(520, 100),
    );
  });
}
