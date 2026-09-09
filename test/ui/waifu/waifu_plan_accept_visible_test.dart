// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: a long plan body grew the editor to 16 lines inside a
// 280px stage; Accept → Build sat below the clip. Scrolling the text
// field never revealed the buttons.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

final _longPlanMd =
    '''
---
id: swift-epub-reader
slug: swift-epub-reader
title: Swift EPUB Reader with Metal GPU Acceleration (macOS Apple Silicon)
goal: GPU page turns
status: draft
steps:
- id: s1
  title: Scaffold the app
  status: pending
---

${List.generate(40, (i) => 'Architecture line $i.\n').join()}
''';

void main() {
  testWidgets('Accept → Build stays hit-testable on a long draft', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.plan,
      activePlanPath: '.waifu/plans/swift-epub-reader.md',
    );
    final seeded = waifuPlanParse(
      _longPlanMd,
      relativePath: session.activePlanPath!,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              WaifuPlanStage(session: session, initialPlan: seeded),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('waifu-plan-title')), findsOneWidget);
    expect(
      find.byKey(const Key('waifu-plan-accept')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('waifu-plan-revise')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('waifu-plan-discard')).hitTestable(),
      findsOneWidget,
    );
  });
}
