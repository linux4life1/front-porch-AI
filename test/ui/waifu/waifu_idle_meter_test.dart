// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('context bar shows idle system+tools, not 0 / N', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness),
      ),
    );
    expect(session.tokensUsed, greaterThan(0));
    expect(find.text('0 / ${session.contextBudget}'), findsNothing);
    expect(
      find.text('${session.tokensUsed} / ${session.contextBudget}'),
      findsOneWidget,
    );
  });
}
