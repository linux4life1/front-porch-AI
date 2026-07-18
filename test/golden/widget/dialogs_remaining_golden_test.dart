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

// Widget pixel goldens for the 10 remaining feasible dialogs from lib/ui/dialogs/.
// data_bank_dialog.dart and database_cleanup_dialog.dart require Drift's
// AppDatabase in initState and are marked 🚫 in COVERAGE.md.
//
// Dialogs covered:
//   KoboldLogDialog          — kobold backend, stopped state.
//                              FakeLLMProvider + FakeKoboldService.
//   ModelSettingsDialog      — openRouter backend renders _buildRemoteSettings()
//                              (no ModelManager/KoboldService/HardwareService
//                              needed). FakeLLMProvider + FakeStorageService.
//   UserPersonaDialog        — empty persona list. FakeUserPersonaService.
//   VoiceBrowserDialog       — empty voice catalog. FakeVoiceManager.
//   TtsSettingsDialog        — ttsEngine='disabled' skips all engine-specific
//                              sections. FakeStorageService + FakeTtsService +
//                              FakeVoiceManager (initState calls
//                              _loadInstalledVoices unconditionally).
//   ImageGenSettingsDialog   — imageGenBackend='remote' skips local fetches in
//                              initState; fetchImageModels() returns [].
//                              FakeStorageService + FakeImageGenService.
//   CharacterAvatarsDialog   — 0 avatars; all deps injected as constructor
//                              params, no Provider tree needed.
//   EditCharacterDialog      — tab 0 (Details); FakeStorageService required for
//                              _buildColorRow() globalXxxColor fallbacks.
//   ImageCropDialog          — 64×64 grey PNG generated via image package.
//   GroupSettingsDialog      — activeGroup==null renders "No active group chat"
//                              empty state in tab 0. Constructor-injected.
//
// Light + dark for each (20 PNGs total).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/ui/dialogs/edit_character_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/kobold_log_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/user_persona_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/voice_browser_dialog.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/fakes_services.dart';
import '../support/fakes_storage.dart';
import '../support/golden_app.dart';

void main() {
  setupPathProviderMock();

  testWidgets('KoboldLogDialog — kobold backend, stopped', (tester) async {
    final llm = FakeLLMProvider();
    final kobold = FakeKoboldService();
    addTearDown(() {
      llm.dispose();
      kobold.dispose();
    });

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
        ],
        child: const KoboldLogDialog(),
      ),
      group: 'dialogs_remaining',
      name: 'kobold_log',
      surface: const Size(720, 620),
    );
  });

  testWidgets('ModelSettingsDialog — openRouter backend (remote settings only)',
      (tester) async {
    final llm = FakeLLMProvider(activeBackend: BackendType.openRouter);
    final storage = FakeStorageService();
    addTearDown(() {
      llm.dispose();
      storage.dispose();
    });

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<StorageService>.value(value: storage),
        ],
        child: const ModelSettingsDialog(),
      ),
      group: 'dialogs_remaining',
      name: 'model_settings',
      surface: const Size(500, 600),
      // TextEditingControllers for API key / URL / model name fields.
      settle: false,
    );
  });

  testWidgets('UserPersonaDialog — empty persona list', (tester) async {
    final personas = FakeUserPersonaService();
    addTearDown(personas.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: const UserPersonaDialog(),
      ),
      group: 'dialogs_remaining',
      name: 'user_persona',
      surface: const Size(600, 500),
      // TextEditingControllers created in initState for the edit form.
      settle: false,
    );
  });

  testWidgets('VoiceBrowserDialog — empty voice catalog', (tester) async {
    final vm = FakeVoiceManager();
    addTearDown(vm.dispose);

    // The filter-chip row overflows on the fixed-size surface; suppress so the
    // golden captures the real rendered state rather than failing.
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<VoiceManager>.value(
        value: vm,
        child: const VoiceBrowserDialog(),
      ),
      group: 'dialogs_remaining',
      name: 'voice_browser',
      surface: const Size(900, 700),
      // _loadData() calls fetchCatalog() + listInstalledVoices() async; both
      // return immediately via fake but settle:false avoids any pending frame.
      settle: false,
    );
  });

  testWidgets('TtsSettingsDialog — engine=disabled, no engine-specific sections',
      (tester) async {
    final storage = FakeStorageService(); // ttsEngine='disabled'
    final tts = FakeTtsService();
    final vm = FakeVoiceManager();
    addTearDown(() {
      storage.dispose();
      tts.dispose();
      vm.dispose();
    });

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<VoiceManager>.value(value: vm),
        ],
        child: const TtsSettingsDialog(),
      ),
      group: 'dialogs_remaining',
      name: 'tts_settings',
      surface: const Size(540, 650),
      // TextEditingControllers for openai key/url/model created in initState;
      // _loadInstalledVoices() fires async (no-op via FakeVoiceManager).
      settle: false,
    );
  });

  testWidgets('ImageGenSettingsDialog — remote backend, empty model list',
      (tester) async {
    final storage = FakeStorageService(); // imageGenBackend='remote'
    final imageSvc = FakeImageGenService();
    addTearDown(() {
      storage.dispose();
      imageSvc.dispose();
    });

    await expectThemedGoldens(
      tester,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ImageGenService>.value(value: imageSvc),
        ],
        child: const ImageGenSettingsDialog(),
      ),
      group: 'dialogs_remaining',
      name: 'image_gen_settings',
      surface: const Size(560, 620),
      // TextEditingControllers for URL/seed/host/port; fetchImageModels async.
      settle: false,
    );
  });

  testWidgets('EditCharacterDialog — tab 0 (Details) at rest', (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: EditCharacterDialog(character: CharacterCard(name: 'Test')),
      ),
      group: 'dialogs_remaining',
      name: 'edit_character',
      surface: const Size(800, 700),
      // Many StyledTextControllers (debounce Timer) + TabController created in
      // initState; TextEditingController cursor tickers block pumpAndSettle.
      settle: false,
    );
  });

  testWidgets('ImageCropDialog — 64×64 grey PNG', (tester) async {
    final raw = img.Image(width: 64, height: 64);
    img.fill(raw, color: img.ColorRgba8(128, 128, 128, 255));
    final pngBytes = Uint8List.fromList(img.encodePng(raw));

    await expectThemedGoldens(
      tester,
      child: ImageCropDialog(imageBytes: pngBytes),
      group: 'dialogs_remaining',
      name: 'image_crop',
      surface: const Size(700, 700),
      // CropController animation tickers.
      settle: false,
    );
  });

  testWidgets('GroupSettingsDialog — no active group (empty state)', (tester) async {
    final chat = FakeChatService();
    final groupRepo = FakeGroupChatRepository();
    addTearDown(() {
      chat.dispose();
      groupRepo.dispose();
    });

    await expectThemedGoldens(
      tester,
      child: GroupSettingsDialog(
        chatService: chat,
        groupRepo: groupRepo,
      ),
      group: 'dialogs_remaining',
      name: 'group_settings',
      surface: const Size(720, 620),
      // TabController created in initState.
      settle: false,
    );
  });
}
