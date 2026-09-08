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
  test('page mounts WaifuPlanStage on the main column', () {
    final sidebar = File('lib/ui/waifu/waifu_sidebar.dart').readAsStringSync();
    final page = File('lib/ui/waifu/waifu_page.dart').readAsStringSync();
    expect(page, contains('WaifuPlanStage'));
    expect(page, contains('waifuTrySetMode'));
    expect(page, contains('kWaifuPlanBuildGateCue'));
    expect(sidebar, isNot(contains('WaifuPlanPanel')));
    expect(sidebar, isNot(contains("id: 'waifu_plan'")));
  });

  test('Accept → Build flips mode and writes accepted status', () async {
    final root = await Directory.systemTemp.createTemp('waifu_plan_accept_');
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
    final seeded = waifuPlanParse(_planMd, relativePath: rel);
    await harness.acceptActivePlan(editedBody: waifuPlanEncode(seeded));
    expect(session.mode, WaifuMode.build);
    expect(session.activePlanPath, rel);
    expect(
      waifuPlanParse(await file.readAsString()).status,
      WaifuPlanStatus.accepted,
    );
  });

  testWidgets('main-stage Accept button is bound', (tester) async {
    final session = WaifuSession(
      folderRoot: Directory.systemTemp.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.plan,
      activePlanPath: '.waifu/plans/empty-email.md',
    );
    final seeded = waifuPlanParse(
      _planMd,
      relativePath: session.activePlanPath!,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Container(
              key: const Key('waifu-plan-stage'),
              child: WaifuPlanPanel(
                session: session,
                harness: WaifuHarness(
                  session: session,
                  llm: ScriptedWaifuLlm(const []),
                ),
                initialPlan: seeded,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('waifu-plan-stage')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-panel')), findsOneWidget);
    expect(find.byKey(const Key('waifu-plan-accept')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('waifu-plan-accept')))
          .onPressed,
      isNotNull,
    );
    expect(session.mode, WaifuMode.plan);
    final panelSrc = File(
      'lib/ui/waifu/waifu_plan_panel.dart',
    ).readAsStringSync();
    expect(panelSrc, contains('acceptActivePlan'));
    expect(panelSrc, contains("'Accepted — Build'"));
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('draft plan blocks Build; freeform Build does not', () async {
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
    expect(
      await waifuTrySetMode(session: draft, next: WaifuMode.build),
      WaifuModeApply.blockedDraft,
    );
    expect(draft.mode, WaifuMode.plan);

    final freeRoot = await Directory.systemTemp.createTemp('waifu_plan_free_');
    addTearDown(() async {
      if (await freeRoot.exists()) await freeRoot.delete(recursive: true);
    });
    final free = WaifuSession(
      folderRoot: freeRoot.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.plan,
    );
    expect(
      await waifuTrySetMode(session: free, next: WaifuMode.build),
      WaifuModeApply.applied,
    );
    expect(free.mode, WaifuMode.build);
  });

  testWidgets('Build chip is on the mode bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuModeBar(mode: WaifuMode.plan, onChanged: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('waifu-mode-build')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
