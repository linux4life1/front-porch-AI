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

// Widget pixel goldens for five app pages that have been deferred until their
// service fakes were ready.
//
// Pages:
//   CreateCharacterPage  — 7-step manual wizard; step 0 (Identity) shown at rest.
//                          All Provider.of calls are inside onPressed lambdas so
//                          no providers are required for a static golden.
//   UserPersonaPage      — empty persona list; renders the "Add your first
//                          persona" empty state via FakeUserPersonaService.
//   ModelManagerPage     — My Models tab, empty local list; FakeModelManager +
//                          FakeHardwareService + FakeStorageService wire the three
//                          build-time Provider.of reads.
//   WorldManagementPage  — empty world list; FakeWorldRepository.
//
// Light + dark for each.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/pages/create_character_page.dart';
import 'package:front_porch_ai/ui/pages/model_manager_page.dart';
import 'package:front_porch_ai/ui/pages/user_persona_page.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/fakes_services.dart';
import '../support/fakes_storage.dart';
import '../support/golden_app.dart';

void main() {
  setupPathProviderMock();

  testWidgets('CreateCharacterPage — step 0 Identity at rest', (tester) async {
    // All Provider.of calls (AppState, CharacterRepository, StorageService) are
    // inside onPressed callbacks and _saveCharacter — never evaluated at build
    // time. No provider tree needed.
    await expectThemedGoldens(
      tester,
      child: const CreateCharacterPage(),
      group: 'pages',
      name: 'create_character',
      surface: const Size(1280, 900),
      // TextEditingControllers (name, tags) and StyledTextControllers (description
      // etc.) start cursor tickers when pumped — pumpAndSettle never returns.
      settle: false,
    );
  });

  testWidgets('UserPersonaPage — empty persona list', (tester) async {
    final personaService = FakeUserPersonaService();
    addTearDown(personaService.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UserPersonaService>.value(
        value: personaService,
        child: const UserPersonaPage(),
      ),
      group: 'pages',
      name: 'user_persona',
      surface: const Size(1280, 900),
      // AnimationController.repeat() drives the header glow — pumpAndSettle
      // blocks on the perpetual ticker.
      settle: false,
    );
  });

  testWidgets('ModelManagerPage — My Models tab, empty list', (tester) async {
    final modelManager = FakeModelManager();
    addTearDown(modelManager.dispose);
    final hardware = FakeHardwareService();
    addTearDown(hardware.dispose);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelManager>.value(value: modelManager),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<StorageService>.value(value: storage),
        ],
        child: const ModelManagerPage(),
      ),
      group: 'pages',
      name: 'model_manager',
      surface: const Size(1280, 900),
    );
  });

  testWidgets('WorldManagementPage — empty world list', (tester) async {
    final worldRepo = FakeWorldRepository();
    addTearDown(worldRepo.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<WorldRepository>.value(
        value: worldRepo,
        child: const WorldManagementPage(),
      ),
      group: 'pages',
      name: 'world_management',
      surface: const Size(1280, 900),
      // AnimationController.repeat() drives the header glow — pumpAndSettle
      // blocks on the perpetual ticker.
      settle: false,
    );
  });
}
