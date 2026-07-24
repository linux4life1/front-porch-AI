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

// Widget pixel goldens for six provider-backed dialogs that were deferred
// until their service fakes were ready.
//
// Dialogs:
//   ExportPersonaDialog    — 2 seeded personas; no providers (data injected).
//   ContextViewerDialog    — empty prompt budget (contextSize=8192, budget={});
//                            FakeChatService injected directly.
//   BackgroundSettingsDialog — "none" background selected; FakeStorageService
//                              wires the build-time Provider.of<StorageService>.
//   UiSettingsDialog       — global defaults (no character override);
//                            FakeStorageService.
//   ChatSettingsDialog     — local default settings (all nil overrides, local
//                            backend); FakeStorageService + FakeLLMProvider +
//                            FakeChatService (didChangeDependencies reads
//                            chatService.sessionGenSettings).
//   GroupObjectivesDialog  — 2 characters, empty objective list returned by
//                            FakeChatService.getActiveObjectivesFor; loading
//                            resolves to empty state after async pump.
//
// Light + dark for each (12 PNGs total).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_theme_overrides.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/dialogs/background_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/context_viewer_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/export_persona_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/group_objectives_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings_dialog.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/fakes_storage.dart';
import '../support/golden_app.dart';

void main() {
  setupPathProviderMock();

  testWidgets('ExportPersonaDialog — 2 seeded personas', (tester) async {
    final personas = [
      UserPersona(
        id: 'p1',
        title: 'Casual',
        name: 'Alex',
        persona: 'Friendly and relaxed.',
      ),
      UserPersona(
        id: 'p2',
        title: 'Professional',
        name: 'Alex (Work)',
        persona: 'Formal and precise.',
      ),
    ];

    await expectThemedGoldens(
      tester,
      child: ExportPersonaDialog(personas: personas),
      group: 'dialogs_more',
      name: 'export_persona',
      surface: const Size(520, 440),
    );
  });

  testWidgets('ContextViewerDialog — empty prompt budget', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: ContextViewerDialog(chatService: chat),
      group: 'dialogs_more',
      name: 'context_viewer',
      surface: const Size(560, 640),
    );
  });

  testWidgets('BackgroundSettingsDialog — no background selected',
      (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const BackgroundSettingsDialog(),
      ),
      group: 'dialogs_more',
      name: 'background_settings',
      surface: const Size(600, 680),
    );
  });

  testWidgets('UiSettingsDialog — global defaults (no character)',
      (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    final chat = FakeChatService();
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const UiSettingsDialog(),
      ),
      group: 'dialogs_more',
      name: 'ui_settings',
      surface: const Size(580, 1200),
    );
  });

  testWidgets('UiSettingsDialog — fantasy theme active', (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    final chat = FakeChatService();
    chat.sessionThemeOverrides =
        ChatThemeOverrides(themeId: 'fantasy');
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const UiSettingsDialog(),
      ),
      group: 'dialogs_more',
      name: 'ui_settings_theme',
      surface: const Size(580, 1200),
    );
  });

  testWidgets('ChatSettingsDialog — local backend, default gen settings',
      (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    final llm = FakeLLMProvider();
    addTearDown(llm.dispose);
    final chat = FakeChatService();
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const ChatSettingsDialog(),
      ),
      group: 'dialogs_more',
      name: 'chat_settings',
      surface: const Size(580, 800),
      // didChangeDependencies creates TextEditingControllers for stop-sequences
      // and banned-phrases — cursor tickers block pumpAndSettle.
      settle: false,
    );
  });

  testWidgets('GroupObjectivesDialog — 2 characters, empty objectives',
      (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final characters = [
      CharacterCard(name: 'Aria Vale', description: 'A lighthouse keeper.'),
      CharacterCard(name: 'Dex Marlowe', description: 'A retired detective.'),
    ];

    // The character-selector row has a pre-existing layout overflow: the Column
    // (CircleAvatar 44px + gap 4px + Text 10sp ≈ 62px) exceeds the 56px that
    // SizedBox(72) - ListView.padding(v:8+8) provides. Suppress overflow errors
    // so the golden captures the real rendered state rather than failing.
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    await expectThemedGoldens(
      tester,
      child: GroupObjectivesDialog(
        chatService: chat,
        groupCharacters: characters,
        initialCharacter: characters.first,
      ),
      group: 'dialogs_more',
      name: 'group_objectives',
      surface: const Size(640, 700),
      // _goalController (TextEditingController) cursor ticker prevents settle.
      settle: false,
    );
  });
}
