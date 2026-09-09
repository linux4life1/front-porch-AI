// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: harness?.acceptActivePlan on a null harness still flashed
// "Accepted — Build" while mode stayed Plan and the file stayed draft.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

const _planMd = '''
---
id: swift-epub-reader
slug: swift-epub-reader
title: Swift EPUB reader
goal: GPU page turns
status: draft
steps:
- id: s1
  title: Scaffold
  status: pending
---

# Swift EPUB reader
''';

void main() {
  testWidgets('Accept without a harness does not fake success', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.plan,
      activePlanPath: '.waifu/plans/swift-epub-reader.md',
    );
    final seeded = waifuPlanParse(
      _planMd,
      relativePath: session.activePlanPath!,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WaifuPlanPanel(session: session, initialPlan: seeded),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('waifu-plan-accept')), findsOneWidget);
    await tester.tap(find.byKey(const Key('waifu-plan-accept')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Accepted — Build'), findsNothing);
    expect(find.text('Could not apply.'), findsOneWidget);
    expect(session.mode, WaifuMode.plan);
  });

  test('plan stage is wired to _harnessOf, not a possibly-null _created', () {
    final src = File('lib/ui/waifu/waifu_page.dart').readAsStringSync();
    expect(src, contains('final harness = _harnessOf(context);'));
    expect(src, contains('WaifuPlanStage('));
  });
}
