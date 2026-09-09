// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  testWidgets('composer stays typeable and can queue while she is busy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    session.running = true;
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm([const LlmToolResponse(calls: [], text: 'later')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness),
      ),
    );
    final field = tester.widget<TextField>(
      find.byKey(const Key('waifu-composer')),
    );
    expect(field.enabled, isTrue);
    expect(find.byKey(const Key('waifu-send')), findsOneWidget);
    expect(find.textContaining('Queue a follow-up for Iris'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('waifu-composer')), 'next job');
    await tester.tap(find.byKey(const Key('waifu-send')));
    await tester.pump();
    expect(session.queued, ['next job']);
    expect(find.byKey(const Key('waifu-queued-0')), findsOneWidget);
    expect(find.text('next job'), findsWidgets);
  });
}
