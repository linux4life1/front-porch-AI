// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: an accepted pin kept the 280px Plan card (and Accept →
// Build) on the main stage after the session was already in Build.

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
status: accepted
---

# Swift EPUB reader
''';

void main() {
  test('Build/Yolo hide the Plan stage even with a pinned plan', () {
    final pin = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.build,
      activePlanPath: '.waifu/plans/swift-epub-reader.md',
    );
    expect(waifuPlanStageVisible(pin), isFalse);
    pin.mode = WaifuMode.yolo;
    expect(waifuPlanStageVisible(pin), isFalse);
    pin.mode = WaifuMode.plan;
    expect(waifuPlanStageVisible(pin), isTrue);
  });

  testWidgets('accepted Build session does not mount the Plan card', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.build,
      activePlanPath: '.waifu/plans/swift-epub-reader.md',
    );
    final seeded = waifuPlanParse(
      _planMd,
      relativePath: session.activePlanPath!,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuPlanStage(session: session, initialPlan: seeded),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('waifu-plan-stage')), findsNothing);
    expect(find.byKey(const Key('waifu-plan-accept')), findsNothing);
  });
}
