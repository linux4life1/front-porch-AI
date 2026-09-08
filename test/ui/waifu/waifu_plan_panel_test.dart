// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:path/path.dart' as p;

const _planMd = '''
---
id: empty-email
slug: empty-email
title: Empty email fix
goal: Make the empty-email test pass
status: draft
steps:
- id: s1
  title: Add failing test
  status: pending
---

# Empty email fix
''';

void main() {
  test('main stage hosts the Plan panel; sidebar does not', () {
    final sidebar = File('lib/ui/waifu/waifu_sidebar.dart').readAsStringSync();
    final page = File('lib/ui/waifu/waifu_page.dart').readAsStringSync();
    expect(page, contains('WaifuPlanStage'));
    expect(page, contains('harness: harness'));
    expect(sidebar, isNot(contains('WaifuPlanPanel')));
    expect(sidebar, isNot(contains("id: 'waifu_plan'")));
  });

  testWidgets('main-stage Accept → Build flips the session mode', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('waifu_plan_ui_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    const rel = '.waifu/plans/empty-email.md';
    final file = File(p.join(root.path, rel));
    await file.create(recursive: true);
    await file.writeAsString(_planMd);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.plan,
      activePlanPath: rel,
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const []),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('waifu-plan-stage')), findsOneWidget);

    for (
      var i = 0;
      i < 20 && find.byKey(const Key('waifu-plan-accept')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byKey(const Key('waifu-plan-accept')), findsOneWidget);
    expect(session.mode, WaifuMode.plan);

    await tester.ensureVisible(find.byKey(const Key('waifu-plan-accept')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-plan-accept')));
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (session.mode != WaifuMode.build &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(session.mode, WaifuMode.build);
    expect(session.activePlanPath, rel);
    expect(
      waifuPlanParse(await file.readAsString()).status,
      WaifuPlanStatus.accepted,
    );
    expect(find.text('Accepted — Build'), findsOneWidget);
  });

  testWidgets('Plan mode mounts the panel on the main stage', (tester) async {
    final root = await Directory.systemTemp.createTemp('waifu_plan_stage_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.plan,
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, harness: harness),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('waifu-plan-stage')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-panel')), findsOneWidget);
    expect(find.textContaining('No plan file yet'), findsOneWidget);
  });

  testWidgets('draft plan blocks the Build chip; freeform Build does not', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('waifu_plan_gate_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    const rel = '.waifu/plans/empty-email.md';
    await File(p.join(root.path, rel)).create(recursive: true);
    await File(p.join(root.path, rel)).writeAsString(_planMd);
    final draft = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.plan,
      activePlanPath: rel,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(
          session: draft,
          harness: WaifuHarness(
            session: draft,
            llm: ScriptedWaifuLlm(const []),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-mode-build')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    expect(draft.mode, WaifuMode.plan);
    expect(find.textContaining('draft plan'), findsWidgets);

    final freeRoot = await Directory.systemTemp.createTemp('waifu_plan_free_');
    addTearDown(() async {
      if (await freeRoot.exists()) await freeRoot.delete(recursive: true);
    });
    final free = WaifuSession(
      folderRoot: freeRoot.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.plan,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(
          session: free,
          harness: WaifuHarness(session: free, llm: ScriptedWaifuLlm(const [])),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-mode-build')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    expect(free.mode, WaifuMode.build);
  });
}
