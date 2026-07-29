// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/dialogs/message_edit_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  testWidgets('opens fullscreen editor and splits think from body',
      (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showMessageEditDialog(
                  context: context,
                  initialText:
                      '<think>Careful analysis.</think>\n"Hello," she said.',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Message'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Body is shown without raw tags; thinking section is expanded.
    expect(find.textContaining('<think>'), findsNothing);
    expect(find.textContaining('"Hello," she said.'), findsWidgets);
    expect(find.textContaining('Careful analysis.'), findsWidgets);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!, contains('<think>'));
    expect(saved!, contains('Careful analysis.'));
    expect(saved!, contains('"Hello," she said.'));
  });

  testWidgets('Save writes body-only when thinking is cleared', (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await showMessageEditDialog(
                  context: context,
                  initialText: '<think>drop me</think>\nKeep this.',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Clear thinking field (first AppTextField is thinking when expanded).
    final fields = find.byType(AppTextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, 'Keep this.');
  });
}
