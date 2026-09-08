// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';
import 'package:front_porch_ai/ui/waifu/waifu_plan_panel.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_plan_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<WaifuSession> seeded() async {
    const rel = '.waifu/plans/empty-email.md';
    final file = File(p.join(root.path, rel));
    await file.create(recursive: true);
    await file.writeAsString('''
---
id: empty-email
slug: empty-email
title: Empty email fix
goal: Make the empty-email test pass
status: draft
steps:
- id: s1
  title: Add failing test
  detail: cover empty
  verify: flutter test
  status: pending
  files:
    - test/parser_test.dart
---

# Empty email fix
''');
    return WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      mode: WaifuMode.plan,
      activePlanPath: rel,
    );
  }

  testWidgets('Plan panel is a real editor, not a mode chip', (tester) async {
    final session = await seeded();
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const []),
    );
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('waifu-mode-plan')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-panel')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-accept')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-revise')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-discard')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-body')), findsOneWidget);
    expect(find.textContaining('Empty email fix'), findsWidgets);
    expect(find.textContaining('Add failing test'), findsWidgets);
  });

  testWidgets('Accept → Build syncs todos and flips the gear', (tester) async {
    final session = await seeded();
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm([const LlmToolResponse(calls: [], text: 'idle')]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WaifuPlanPanel(session: session, harness: harness),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('waifu-plan-accept')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waifu-plan-accept')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(session.mode, WaifuMode.build);
    expect(
      harness.todos.items.map((t) => t.content),
      contains('Add failing test'),
    );
    expect(find.textContaining('Accepted — Build'), findsOneWidget);
  });
}
