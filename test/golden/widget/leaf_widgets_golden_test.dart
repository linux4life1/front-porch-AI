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

// Widget pixel goldens for stateless prop-only leaf widgets in
// lib/ui/widgets/ and lib/ui/chat_components/widgets/.
//
// None of these widgets read providers at build time; all data flows through
// constructor params. pumpAndSettle is safe (no perpetual timers/tickers).
//
// Cases:
//   SettingsMenuItem   — icon + label
//   FixationChip       — compact variant; expanded with lifespan
//   RealismProgressRow — positive bond "Close" tier; negative trust red
//   NsfwToggle         — off state; on state
//   StyledDropdown     — three string options
//   SliderWithInput    — mid-range float value (Builder for context param)
//   LocalModelCard     — seeded Q4_K_M model, 8 GB
//   RealismFormSection — enabled state, all required params as no-ops
//   NeedsFormSection   — enabled state, all per-need baselines set

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/local_model_info.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart'
    show SettingsMenuItem;
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show FixationChip, RealismProgressRow, SliderWithInput;
import 'package:front_porch_ai/ui/widgets/local_model_card.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/nsfw_toggle.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/styled_dropdown.dart';

import '../support/creator_test_support.dart';
import '../support/golden_app.dart';

LocalModelInfo _modelFixture() => LocalModelInfo(
  path: '/models/llama-3-8B-Q4_K_M.gguf',
  filename: 'llama-3-8B-Q4_K_M.gguf',
  sizeBytes: 4_831_838_208,
  modified: DateTime(2026, 1, 1),
  paramCountB: 8.0,
);

Widget _realismForm() => RealismFormSection(
  enabled: true,
  onEnabledChanged: (_) {},
  timeOfDay: 'evening',
  onTimeOfDayChanged: (_) {},
  dayCount: 3,
  onDayCountChanged: (_) {},
  shortTermBond: 120,
  onShortTermBondChanged: (_) {},
  longTermBond: 60,
  onLongTermBondChanged: (_) {},
  trustLevel: 40,
  onTrustLevelChanged: (_) {},
  emotion: 'neutral',
  onEmotionChanged: (_) {},
  emotionIntensity: 'moderate',
  onEmotionIntensityChanged: (_) {},
  nsfwCooldownEnabled: false,
  onNsfwCooldownChanged: (_) {},
  chaosModeEnabled: false,
  onChaosModeChanged: (_) {},
  realismVerificationEnabled: true,
  onRealismVerificationChanged: (_) {},
);

Widget _needsForm() => NeedsFormSection(
  enabled: true,
  onEnabledChanged: (_) {},
  enjoysLowHygiene: false,
  onEnjoysLowHygieneChanged: (_) {},
  baselineHunger: 70,
  onBaselineHungerChanged: (_) {},
  baselineBladder: 55,
  onBaselineBladderChanged: (_) {},
  baselineEnergy: 80,
  onBaselineEnergyChanged: (_) {},
  baselineSocial: 45,
  onBaselineSocialChanged: (_) {},
  baselineFun: 65,
  onBaselineFunChanged: (_) {},
  baselineHygiene: 75,
  onBaselineHygieneChanged: (_) {},
  baselineComfort: 60,
  onBaselineComfortChanged: (_) {},
);

void main() {
  setupPathProviderMock();

  testWidgets('SettingsMenuItem — icon + label', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const SettingsMenuItem(
        icon: Icons.tune,
        label: 'Realism Settings',
      ),
      group: 'leaf_widgets',
      name: 'settings_menu_item',
      surface: const Size(300, 80),
    );
  });

  testWidgets('FixationChip — compact', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const FixationChip(topic: 'mystery novels', compact: true),
      group: 'leaf_widgets',
      name: 'fixation_chip_compact',
      surface: const Size(250, 60),
    );
  });

  testWidgets('FixationChip — expanded with lifespan', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const FixationChip(
        topic: 'stargazing together',
        lifespan: 8,
        compact: false,
      ),
      group: 'leaf_widgets',
      name: 'fixation_chip_expanded',
      surface: const Size(300, 100),
    );
  });

  testWidgets('RealismProgressRow — positive bond Close tier', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const RealismProgressRow(
        label: 'Bond',
        value: 120,
        tier: 3,
        tierName: 'Close',
        color: Colors.pinkAccent,
        icon: Icons.favorite,
      ),
      group: 'leaf_widgets',
      name: 'realism_progress_positive',
      surface: const Size(440, 80),
    );
  });

  testWidgets('RealismProgressRow — negative trust red', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const RealismProgressRow(
        label: 'Trust',
        value: -60,
        tier: -2,
        tierName: 'Suspicious',
        color: Colors.redAccent,
        icon: Icons.shield_outlined,
      ),
      group: 'leaf_widgets',
      name: 'realism_progress_negative',
      surface: const Size(440, 80),
    );
  });

  testWidgets('NsfwToggle — off state', (tester) async {
    await expectThemedGoldens(
      tester,
      child: NsfwToggle(
        value: false,
        accentColor: Colors.deepPurpleAccent,
        onChanged: (_) {},
      ),
      group: 'leaf_widgets',
      name: 'nsfw_toggle_off',
      surface: const Size(360, 90),
    );
  });

  testWidgets('NsfwToggle — on state', (tester) async {
    await expectThemedGoldens(
      tester,
      child: NsfwToggle(
        value: true,
        accentColor: Colors.deepPurpleAccent,
        onChanged: (_) {},
      ),
      group: 'leaf_widgets',
      name: 'nsfw_toggle_on',
      surface: const Size(360, 90),
    );
  });

  testWidgets('StyledDropdown — three string options', (tester) async {
    await expectThemedGoldens(
      tester,
      child: StyledDropdown<String>(
        value: 'morning',
        items: const [
          DropdownMenuItem(value: 'dawn', child: Text('Dawn')),
          DropdownMenuItem(value: 'morning', child: Text('Morning')),
          DropdownMenuItem(value: 'evening', child: Text('Evening')),
        ],
        onChanged: null,
        width: 240,
      ),
      group: 'leaf_widgets',
      name: 'styled_dropdown',
      surface: const Size(300, 80),
    );
  });

  testWidgets('SliderWithInput — mid-range float', (tester) async {
    await expectThemedGoldens(
      tester,
      // SliderWithInput requires a BuildContext constructor param (used for
      // theming in callbacks). Builder provides it from the live widget tree.
      child: Builder(
        builder: (ctx) => SliderWithInput(
          label: 'Temperature',
          value: 0.75,
          min: 0.0,
          max: 2.0,
          onChanged: (_) {},
          context: ctx,
          divisions: 20,
          tooltip: 'Sampling temperature',
        ),
      ),
      group: 'leaf_widgets',
      name: 'slider_with_input',
      surface: const Size(460, 100),
    );
  });

  testWidgets('LocalModelCard — 8B Q4_K_M model', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 520,
        child: LocalModelCard(
          model: _modelFixture(),
          availableVramMb: 8192,
          onDelete: () {},
        ),
      ),
      group: 'leaf_widgets',
      name: 'local_model_card',
      surface: const Size(580, 140),
    );
  });

  testWidgets('RealismFormSection — enabled state', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 520, child: _realismForm()),
      group: 'leaf_widgets',
      name: 'realism_form_section',
      surface: const Size(580, 1400),
    );
  });

  testWidgets('NeedsFormSection — enabled with all baselines', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 520, child: _needsForm()),
      group: 'leaf_widgets',
      name: 'needs_form_section',
      surface: const Size(580, 900),
    );
  });
}
