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
  test('sidebar hosts a real Plan panel, not a mode chip', () {
    final sidebar = File('lib/ui/waifu/waifu_sidebar.dart').readAsStringSync();
    final page = File('lib/ui/waifu/waifu_page.dart').readAsStringSync();
    expect(sidebar, contains('WaifuPlanPanel'));
    expect(sidebar, contains("id: 'waifu_plan'"));
    expect(page, contains('harness: harness'));
  });

  testWidgets('Accept → Build flips the session mode', (tester) async {
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
    final seeded = waifuPlanParse(_planMd, relativePath: rel);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WaifuPlanPanel(
              session: session,
              harness: harness,
              initialPlan: seeded,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('waifu-plan-accept')), findsOneWidget);
    expect(session.mode, WaifuMode.plan);

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
}
