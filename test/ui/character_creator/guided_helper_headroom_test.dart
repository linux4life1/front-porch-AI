// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guided-creator helpers (expand narrative / randomize name / randomize
// concept) send a small think-off budget. Without
// mandatoryReasoningHeadroom they learned a silent reasoner and left the
// field empty. Pin the live call site, not just a matching GenerationParams.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';

import '../../golden/support/creator_test_support.dart';

class _RecordingLlm extends LLMService {
  final List<GenerationParams> seen = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    seen.add(params);
    yield '{"name":"Mara Voss"}';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'headroom-test';
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

void main() {
  setupPathProviderMock();

  test(
    'randomizeName opts into headroom and keeps exclude (no salvage)',
    () async {
      final storage = await makeGoldenStorage();
      addTearDown(storage.dispose);
      final llm = _RecordingLlm();
      final provider = _FakeLLMProvider(
        llm,
        KoboldService(storage),
        OpenRouterService(),
        storage,
        BackendManager(storage),
      );
      addTearDown(provider.dispose);

      final state = CreatorState();
      addTearDown(state.dispose);
      await state.randomizeName(llmProvider: provider, storage: storage);

      expect(llm.seen, isNotEmpty);
      final p = llm.seen.single;
      expect(p.mandatoryReasoningHeadroom, isTrue);
      expect(p.reasoningEnabled, isFalse);
      expect(p.reasoningMaxTokens, 0);
      expect(p.salvageReasoning, isFalse);
      expect(state.nameController.text, 'Mara Voss');
    },
  );
}
