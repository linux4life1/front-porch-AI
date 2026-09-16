// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/worker_backend_section.dart';

void main() {
  testWidgets('dual-local banner names the GPU fight', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WorkerLaneStatusBanners(refusedDualLocal: true)),
      ),
    );

    expect(find.byKey(const Key('worker-dual-local-banner')), findsOneWidget);
    expect(find.textContaining('fight over the GPU'), findsOneWidget);
    expect(find.text(kWorkerDualLocalMessage), findsOneWidget);
  });

  testWidgets('unready copy shows when the pair is allowed', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkerLaneStatusBanners(
            refusedDualLocal: false,
            unreadyMessage:
                'Realism evals are waiting for KoboldCPP to start. Open Models '
                'and make sure a file is loaded.',
          ),
        ),
      ),
    );

    expect(find.textContaining('waiting for KoboldCPP'), findsOneWidget);
    expect(find.text(kWorkerDualLocalMessage), findsNothing);
  });

  testWidgets('no banner when the worker is fine', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: WorkerLaneStatusBanners(refusedDualLocal: false)),
      ),
    );

    expect(find.textContaining('fight over the GPU'), findsNothing);
    expect(find.byType(WorkerLaneWarnBanner), findsNothing);
  });
}
