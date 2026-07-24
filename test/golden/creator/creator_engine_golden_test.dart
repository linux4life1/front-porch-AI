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

// Behavioral goldens for the AI Character Creator ENGINE.
//
// Why this exists: the June-6 "Stage 4" refactor shipped a fraudulent creator to
// stable (see .claude/changelog.md 2026-06-21 "functionally dead"). Two stubs
// slipped through because nothing exercised the engine:
//   1) `startGeneration` was an 800ms delay + a hardcoded dummy card
//      (`personality: 'Brave and clever'`) — it never called the LLM.
//   2) `saveGeneratedCharacter` never persisted — `repo.save` was commented out.
//
// A widget/pixel golden could NOT catch either: the wizard renders identically
// whether Generate calls the model or returns a dummy, and whether Save writes to
// the DB or silently drops it. These are BEHAVIORAL goldens — they assert the
// engine actually drives the LLM and actually persists, and freeze the saved card
// shape so a regression to a stub fails loudly.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';

import '../golden_harness.dart';
import '../support/creator_test_support.dart';

/// A scripted LLM that returns the same canned chargen JSON for every call and
/// counts invocations. The call count is the decisive signal against the
/// "no LLM call / hardcoded dummy" stub: the real engine MUST invoke this.
class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.response);
  final String response;
  int callCount = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    callCount++;
    yield response;
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'scripted-test';
}

/// Minimal LLMProvider whose active service is the scripted fake. The five
/// collaborators are all cheap, test-safe constructors (used elsewhere in the
/// suite); we only override the three getters the engine consults.
class _FakeLLMProvider extends LLMProvider {
  _FakeLLMProvider(this._svc, KoboldService k, OpenRouterService o,
      StorageService s, BackendManager b)
      : super(k, o, s, b);
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
    KoboldService(storage),
    OpenRouterService(),
    storage,
    BackendManager(storage),
  );
}

/// Recursively replace the random save-time `stable_id` with a placeholder so
/// the persisted-shape golden stays deterministic while still proving the field
/// is populated (ensureStableId ran).
Map<String, dynamic> _stabilize(Map<String, dynamic> json) {
  final copy = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
  void walk(dynamic node) {
    if (node is Map) {
      for (final k in node.keys.toList()) {
        if (k == 'stable_id' && node[k] != null) {
          node[k] = '<stableId>';
        } else {
          walk(node[k]);
        }
      }
    } else if (node is List) {
      for (final e in node) {
        walk(e);
      }
    }
  }

  walk(copy);
  return copy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  group('CreatorEngine.saveCharacter — persists a real character', () {
    test('save writes the card (with realism seeding) to the repository '
        'and freezes the saved shape', () async {
      final storage = await makeGoldenStorage();
      final db = AppDatabase.forTesting();
      final repo = CharacterRepository(db, storage);
      addTearDown(() async => db.close());

      final state = CreatorState();
      addTearDown(state.dispose);

      // A generated card plus the user's (possibly edited) field text. The
      // engine copies the controllers onto the card at save time.
      state.generatedCard = CharacterCard(
        name: 'Aria Vale',
        lorebook: Lorebook(entries: [
          LorebookEntry(key: 'keep', content: 'Kept entry.'),
          LorebookEntry(key: 'drop', content: 'Dropped entry.'),
        ]),
      );
      state.descController.text = '{{char}} is a lighthouse keeper.';
      state.personalityController.text = 'Patient, observant, dry-humored.';
      state.scenarioController.text = '{{user}} climbs the tower at dusk.';
      state.firstMessageController.text = 'The lamp turns. "You came, {{user}}."';
      state.exampleDialogueController.text =
          '{{user}}: Hi\n{{char}}: The sea is loud tonight.';
      state.systemPromptController.text = '';

      // Distinctive realism/needs config so the golden captures the seeding the
      // restoration added (and a stub that skipped it would diverge).
      state.realismStepEnabled = true;
      state.realismNeedsSim = true;
      state.realismDayCount = 4;
      state.realismTimeOfDay = 'evening';
      state.needsBaselineHunger = 70;
      state.needsDecayHunger = 6;

      // User unchecked the second lorebook entry in the Review step.
      state.lorebookEntryEnabled = {0: true, 1: false};

      final ok = await state.saveCharacter(repo: repo, storage: storage);

      // 1) The decisive behavioral assertions (kill the "never persisted" stub).
      expect(ok, isTrue, reason: 'saveCharacter must report success');
      expect(repo.characters.length, 1,
          reason: 'the character must reach the repository');
      final saved = repo.characters.single;
      expect(saved.name, 'Aria Vale');
      expect(saved.description, '{{char}} is a lighthouse keeper.');
      expect(saved.personality, 'Patient, observant, dry-humored.');
      expect(saved.lorebook!.entries.length, 1,
          reason: 'unchecked lorebook entries must be dropped');
      expect(saved.lorebook!.entries.single.content, 'Kept entry.');
      expect(saved.frontPorchExtensions?.stableId, isNotNull);
      expect(saved.frontPorchExtensions!.stableId!.isNotEmpty, isTrue,
          reason: 'ensureStableId must run so later edits stay linked');

      // It must also be durable in the DB, not just the in-memory cache.
      final rows = await db.getAllCharacters();
      expect(rows.length, 1);
      expect(rows.single.name, 'Aria Vale');

      // 2) Freeze the exact persisted shape (realism seeding + field mapping).
      expectGoldenJson(_stabilize(saved.toJson()),
          group: 'creator', name: 'saved_card');
    });

    test('save is idempotent: a second save UPDATES in place and keeps the '
        'stableId (the panel saves first, Save & Finish saves again)',
        () async {
      final storage = await makeGoldenStorage();
      final db = AppDatabase.forTesting();
      final repo = CharacterRepository(db, storage);
      addTearDown(() async => db.close());

      final state = CreatorState();
      addTearDown(state.dispose);
      state.generatedCard = CharacterCard(name: 'Aria Vale');
      state.descController.text = 'First draft.';

      expect(await state.saveCharacter(repo: repo, storage: storage), isTrue);
      final firstId = state.generatedCard!.frontPorchExtensions!.stableId;
      expect(firstId, isNotNull);

      // Edit + save again — the flow the Portrait & Avatars panel creates.
      state.descController.text = 'Edited after the panel saved.';
      expect(await state.saveCharacter(repo: repo, storage: storage), isTrue);

      final rows = await db.getAllCharacters();
      expect(rows.length, 1, reason: 'update in place — never a duplicate');
      expect(state.generatedCard!.frontPorchExtensions!.stableId, firstId,
          reason: 'identity must survive the multi-shot save');
      expect(repo.characters.single.description,
          'Edited after the panel saved.');
    });
  });

  group('CreatorEngine.generateFromMode — drives the LLM', () {
    test('generation invokes the model and yields a model-derived card '
        '(not a hardcoded dummy)', () async {
      final storage = await makeGoldenStorage();
      const sentinel = 'ZZSENTINELZZ';
      // One canned chargen JSON, reused for every call in the pipeline. Uses the
      // exact keys the parser knows; >100 stripped chars; no "..." placeholders.
      final canned = jsonEncode({
        'description':
            '$sentinel {{char}} is a wandering cartographer who maps the '
                'drowned coast, sketching ruins the tide reveals at dawn.',
        'personality':
            '$sentinel Curious, meticulous, quietly brave; speaks in measured, '
                'vivid observations and never leaves a map unfinished.',
        'scenario':
            '{{user}} finds {{char}} pinning a half-drawn chart to a tavern wall.',
        'first_message':
            '"You have the look of someone who is also lost," {{char}} says.',
        'example_dialogue': '{{user}}: Hello\n{{char}}: The roads moved again.',
        'system_prompt': '',
        'tags': ['explorer'],
        'image_prompt': 'a cartographer at a candlelit table, portrait',
        'lorebook': {'entries': []},
      });

      final llm = _ScriptedLlm(canned);
      final provider = _makeProvider(llm, storage);
      addTearDown(provider.dispose);
      final personaDb = AppDatabase.forTesting();
      addTearDown(() async => personaDb.close());
      final persona = UserPersonaService(personaDb);
      addTearDown(persona.dispose);

      final state = CreatorState();
      addTearDown(state.dispose);
      state.creatorMode = CreatorMode.quick;
      state.nameController.text = 'Mira Holt';
      state.conceptController.text = 'A cartographer of drowned coasts.';

      await state.generateFromMode(
        llmProvider: provider,
        storage: storage,
        personaService: persona,
      );

      // The decisive signal: the engine actually called the model. The dummy
      // stub made zero LLM calls.
      expect(llm.callCount, greaterThan(0),
          reason: 'the engine must invoke the LLM, not fabricate a card');

      final card = state.generatedCard;
      expect(card, isNotNull, reason: 'a card must be produced');
      expect(card!.name, 'Mira Holt', reason: 'the chosen name passes through');
      expect(card.description.isNotEmpty, isTrue);
      expect(card.personality.isNotEmpty, isTrue);
      expect(card.scenario.isNotEmpty, isTrue);

      // Model-derived content (not a hardcoded constant): the sentinel the fake
      // emitted must survive into the card.
      final blob = '${card.description}\n${card.personality}';
      expect(blob, contains(sentinel),
          reason: 'card fields must come from model output');
      expect(card.personality, isNot(contains('Brave and clever')),
          reason: 'must never reproduce the old dummy');

      // Real post-generation flow state (the wizard advances to Realism).
      expect(state.isGenerating, isFalse);
      expect(state.currentStep, 4);
    });
  });
}
