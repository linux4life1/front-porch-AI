// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Write step Stop is reachable while a bake is in flight.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/write_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

void main() {
  testWidgets('Stop is on the write step and aborts the engine', (
    tester,
  ) async {
    final state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.writing = true;
    state.status = 'Writing 1/3';
    state.engine = WorldFromWikiEngine(
      wiki: WikiSearchService(getBaseUrl: () => ''),
      llm: _SilentLlm(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldFromWikiWriteStep(state: state)),
      ),
    );

    expect(find.byKey(const Key('world-from-wiki-stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('world-from-wiki-stop')));
    await tester.pump();
    expect(state.engine!.aborted, isTrue);
    expect(state.canSave, isFalse);
  });
}

class _SilentLlm extends LLMService {
  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async => null;

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}
