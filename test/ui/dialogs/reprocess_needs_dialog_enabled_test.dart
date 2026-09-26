// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/dialogs/reprocess_needs_dialog.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ({String speaker, List<String> enabled})? target,
  String speaker = 'Aria',
  Future<void> Function(String, Set<String>)? onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReprocessNeedsDialog(
          target: target,
          speaker: speaker,
          onSubmit: onSubmit ?? (_, _) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('two needs off shows five chips and hides the off ones', (
    tester,
  ) async {
    await _pump(
      tester,
      target: (
        speaker: 'Aria',
        enabled: const ['hunger', 'bladder', 'energy', 'social', 'comfort'],
      ),
    );

    expect(find.byType(FilterChip), findsNWidgets(5));
    expect(find.text('Hunger'), findsOneWidget);
    expect(find.text('Comfort'), findsOneWidget);
    expect(find.text('Hygiene'), findsNothing);
    expect(find.text('Fun'), findsNothing);
    expect(find.text(kReprocessNeedsEmptyHelper), findsOneWidget);
  });

  testWidgets('one enabled hides the scope block and submits empty scope', (
    tester,
  ) async {
    Set<String>? scope;
    await _pump(
      tester,
      target: (speaker: 'Aria', enabled: const ['hunger']),
      onSubmit: (critique, onlyNeeds) async {
        expect(critique, 'they ate');
        scope = onlyNeeds;
      },
    );

    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Limit to these needs'), findsNothing);
    expect(
      find.text(reprocessNeedsOneEnabledLine('hunger', 'Aria')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'they ate');
    await tester.tap(find.text('Reprocess'));
    await tester.pumpAndSettle();
    expect(scope, isEmpty);
  });

  testWidgets('zero enabled shows the message and Close only', (tester) async {
    await _pump(tester, target: null, speaker: 'Aria');

    expect(find.text(reprocessNeedsZeroLine('Aria')), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Reprocess'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('empty helper string is exact', (tester) async {
    await _pump(
      tester,
      target: (speaker: 'Aria', enabled: const ['hunger', 'energy']),
    );
    expect(
      find.text('Nothing selected — every need shown here is re-evaluated.'),
      findsOneWidget,
    );
  });
}
