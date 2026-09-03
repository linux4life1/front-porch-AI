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

// TWO SILENT MALFORMED-INPUT BUGS IN THE AI CHARACTER CREATOR.
//
// 1. World lore was thrown away WHOLESALE on a small local context window.
//    `_extractWorldLore` reserves 3K tokens for generation
//    (`contextSize - 3000`); at or below 3000 that limit went negative, the
//    `> limit` test became unconditionally true, and `clamp(0, len)` made the
//    kept-character count 0 — so every character of the gathered lore was
//    dropped and the model was handed the bare "[TRUNCATED…]" marker instead.
//    2048 is not a contrived number: it is the app's OWN low-VRAM
//    recommendation (OptimizationService), applied by a button in this very
//    wizard.
//
// 2. Automated mode built its description by appending fragments to the
//    concept box unconditionally, so an empty concept box produced a
//    description that literally opened with a stray period.
//
// Both proven to fail first: restoring `freeContextLimit = contextSize - 3000`
// with no floor reds test 1, and restoring the bare
// `enriched += '. Physical appearance: …'` reds test 2.

import 'dart:convert';
import 'dart:typed_data';

import 'package:front_porch_ai/utils/picker_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';

import '../../golden/support/creator_test_support.dart';

/// Records every prompt it is asked to generate from and always answers with
/// the same canned card. Same harness shape as `creator_modes_test.dart`'s
/// `_ScriptedLlm` (private there, so it cannot be imported).
class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.response);
  final String response;
  final List<String> capturedPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    capturedPrompts.add(params.prompt);
    yield response;
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'scripted-test';
}

/// A KoboldCpp handle that reports ready without a process, so the world-lore
/// budget takes the LOCAL branch (`contextSize - 3000`) rather than the
/// remote 120K one.
class _ReadyKobold extends KoboldService {
  _ReadyKobold(super.storage);

  @override
  bool get isReady => true;
}

class _FakeLLMProvider extends LLMProvider {
  _FakeLLMProvider(
    this._svc,
    KoboldService k,
    OpenRouterService o,
    StorageService s,
    BackendManager b,
  ) : super(k, o, s, b);
  final LLMService _svc;

  @override
  LLMService get activeService => _svc;
  @override
  BackendType get activeBackend => BackendType.kobold;
  @override
  bool get hasManagedProcess => true;
}

_FakeLLMProvider _makeProvider(LLMService svc, StorageService storage) {
  return _FakeLLMProvider(
    svc,
    _ReadyKobold(storage),
    OpenRouterService(),
    storage,
    BackendManager(storage),
  );
}

String _cannedCardJson() => jsonEncode({
  'description': 'A model-authored description that automated mode replaces.',
  'personality': 'Curious, meticulous, quietly brave.',
  'scenario': '{{user}} finds {{char}} pinning a chart to a tavern wall.',
  'first_message': '"You have the look of someone also lost," {{char}} says.',
  'example_dialogue': '{{user}}: Hello\n{{char}}: The roads moved again.',
  'system_prompt': '',
  'tags': ['explorer'],
  'image_prompt': 'a cartographer at a candlelit table, portrait',
  'lorebook': {'entries': []},
});

Future<UserPersonaService> _makePersonaService() async {
  final db = AppDatabase.forTesting();
  addTearDown(() async => db.close());
  final persona = UserPersonaService(db);
  addTearDown(persona.dispose);
  return persona;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  test(
    'attached world lore still reaches the prompt when the local context '
    'window is at or under the 3K generation reservation',
    () async {
      final storage = await makeGoldenStorage();
      // The app's own low-VRAM recommendation, applied by a button in this
      // same wizard — the exact value that used to erase all lore.
      await storage.setContextSize(2048);

      final llm = _ScriptedLlm(_cannedCardJson());
      final provider = _makeProvider(llm, storage);
      addTearDown(provider.dispose);
      final persona = await _makePersonaService();

      const lore =
          'The Saltmarrow Compact binds the seven tide-houses of Brelth. '
          'Its signatories may not raise a levy above the high-water mark, '
          'and any dispute is settled at the Drowned Assizes on the first '
          'slack tide after midwinter. Breaking the Compact costs a house '
          'its name, its charts and its right to anchor anywhere in the '
          'inner reach.';
      final state = CreatorState();
      addTearDown(state.dispose);
      state.creatorMode = CreatorMode.automated;
      state.nameController.text = 'Sable Marrow';
      state.conceptController.text = 'A tide-house cartographer.';
      state.loreFiles = [
        MemoryPlatformFile(
          name: 'compact.txt',
          bytes: Uint8List.fromList(utf8.encode(lore)),
        ),
      ];

      await state.generateFromMode(
        llmProvider: provider,
        storage: storage,
        personaService: persona,
      );

      expect(llm.capturedPrompts, isNotEmpty);
      final basePrompt = llm.capturedPrompts.first;
      expect(
        basePrompt,
        contains('Saltmarrow Compact'),
        reason: 'the gathered lore must survive a 2048-token context, not be '
            'truncated to zero characters',
      );
      expect(
        basePrompt,
        isNot(contains('TRUNCATED DUE TO CONTEXT LIMITS')),
        reason: 'lore this short needs no truncation marker at all',
      );
    },
  );

  test(
    'automated mode with an empty concept box builds a description that does '
    'not open with a stray period',
    () async {
      final storage = await makeGoldenStorage();
      final llm = _ScriptedLlm(_cannedCardJson());
      final provider = _makeProvider(llm, storage);
      addTearDown(provider.dispose);
      final persona = await _makePersonaService();

      final state = CreatorState();
      addTearDown(state.dispose);
      state.creatorMode = CreatorMode.automated;
      state.nameController.text = 'Sable Marrow';
      // Nothing in the wizard requires this box to be filled.
      state.conceptController.text = '';
      state.race = 'Elf';
      state.bodyType = 'Athletic';
      state.nsfwEnabled = false;

      await state.generateFromMode(
        llmProvider: provider,
        storage: storage,
        personaService: persona,
      );

      final card = state.generatedCard;
      expect(card, isNotNull);
      expect(
        card!.description,
        'Physical appearance: Elf race/species, Athletic build',
        reason: 'the assembled fragments must stand on their own when there '
            'is no concept in front of them',
      );
    },
  );
}
