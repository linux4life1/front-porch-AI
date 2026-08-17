// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Identity sheet: plan-lines editor after Ambitions only when the planner
// flag is on. Add/delete. No Plans / Wings it chips.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/chip_list_editor.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart';
import 'package:front_porch_ai/ui/widgets/plan_lines_editor.dart';

import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester, {
    required bool plannerOn,
    List<String> ambitions = const ['open a bakery'],
    List<String> planLines = const [],
    ValueChanged<List<String>>? onPlanLinesChanged,
  }) async {
    final storage = FakeStorageService();
    if (plannerOn) {
      await storage.realismSettings.setPlannerEnabled(true);
    }
    var lines = List<String>.from(planLines);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => IdentityChipLists(
                  ambitions: ambitions,
                  onAmbitionsChanged: (_) {},
                  planLines: lines,
                  onPlanLinesChanged: (v) {
                    setState(() => lines = v);
                    onPlanLinesChanged?.call(v);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('plan-lines editor is omitted when the flag is off', (tester) async {
    await pump(tester, plannerOn: false, planLines: const ['finish the log']);
    expect(find.byType(PlanLinesEditor), findsNothing);
    expect(find.text('PLAN LINES'), findsNothing);
    expect(find.text('Plans'), findsNothing);
    expect(find.text('Wings it'), findsNothing);
  });

  testWidgets('plan-lines editor appears after Ambitions when flag is on',
      (tester) async {
    await pump(tester, plannerOn: true);
    expect(find.text('Ambitions'), findsOneWidget);
    expect(find.byType(PlanLinesEditor), findsOneWidget);
    expect(find.text('PLAN LINES'), findsOneWidget);
    expect(find.text('Plans'), findsNothing);
    expect(find.text('Wings it'), findsNothing);
    expect(find.byType(ChipListEditor), findsWidgets);

    final ambitions = tester.getTopLeft(find.text('Ambitions'));
    final planHeader = tester.getTopLeft(find.text('PLAN LINES'));
    expect(planHeader.dy, greaterThan(ambitions.dy));
  });

  testWidgets('add and delete a plan line', (tester) async {
    var current = <String>[];
    await pump(
      tester,
      plannerOn: true,
      onPlanLinesChanged: (v) => current = v,
    );

    await tester.tap(find.text('+ add').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'finish the log before the tide');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(current, ['finish the log before the tide']);
    expect(find.text('finish the log before the tide'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove').last);
    await tester.pumpAndSettle();
    expect(current, isEmpty);
  });
}
