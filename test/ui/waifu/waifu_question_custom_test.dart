// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: dialog only returned listed choices or a hard-coded "ok";
// there was no field to type a custom answer like Claude / OpenCode.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  testWidgets('typed custom answer is returned even when choices exist', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const WaifuQuestionDialog(
                    request: WaifuQuestionRequest(
                      prompt: 'Name the helper?',
                      choices: ['foo', 'bar'],
                    ),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('waifu-question-custom')), findsOneWidget);
    expect(find.byKey(const Key('waifu-question-answer')), findsOneWidget);
    expect(find.byKey(const Key('waifu-question-foo')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('waifu-question-custom')),
      '  baz helper  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('waifu-question-answer')));
    await tester.pumpAndSettle();

    expect(result, 'baz helper');
  });

  testWidgets('empty Answer stays put; Skip still cancels', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const WaifuQuestionDialog(
                    request: WaifuQuestionRequest(prompt: 'Any notes?'),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('OK'), findsNothing);
    final answer = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('waifu-question-answer')),
    );
    expect(answer.onPressed, isNull);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(result, '');
  });
}
