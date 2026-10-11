// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

/// Her ask names her, shows the whole command, and answers from the keys.
void main() {
  const longCommand =
      'npm install --save-dev typescript@5 eslint prettier '
      '&& npx tsc --init && npx eslint --init --config standard';

  Future<List<WaifuAskDecision?>> openAsk(WidgetTester tester) async {
    final answers = <WaifuAskDecision?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showDialog<WaifuAskDecision>(
                context: context,
                builder: (_) => const WaifuAskDialog(
                  name: 'Mira',
                  request: WaifuAskRequest(
                    toolName: 'bash',
                    summary: longCommand,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('names her and shows the full command', (tester) async {
    await openAsk(tester);
    expect(find.text('Mira wants to run a command'), findsOneWidget);
    expect(find.byKey(const Key('waifu-dialog-face')), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('waifu-ask-detail')))
          .data,
      longCommand,
    );
  });

  testWidgets('Y allows once', (tester) async {
    final answers = await openAsk(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.pumpAndSettle();
    expect(answers, [WaifuAskDecision.allowOnce]);
  });

  testWidgets('N denies', (tester) async {
    final answers = await openAsk(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(answers, [WaifuAskDecision.deny]);
  });

  testWidgets('Enter takes the default, Allow once', (tester) async {
    final answers = await openAsk(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answers, [WaifuAskDecision.allowOnce]);
  });
}
