// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chip row is this model's real menu — not a fixed Low/Medium/High
// card. DeepSeek :thinking offers High and Max; Grok-style mandatory
// models lock Off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

void main() {
  setUp(clearReasoningEffortCatalog);

  const thinking = 'deepseek/deepseek-v4-flash:thinking';

  Future<void> pumpChips(
    WidgetTester tester, {
    required String value,
    required String modelId,
    required List<String> taps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThinkingStrengthControl(
            value: value,
            modelId: modelId,
            onChanged: taps.add,
          ),
        ),
      ),
    );
  }

  testWidgets(':thinking model shows High and Max, not Low or Medium',
      (tester) async {
    final taps = <String>[];
    await pumpChips(
      tester,
      value: 'medium',
      modelId: thinking,
      taps: taps,
    );

    expect(find.text('Low'), findsNothing);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);

    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(taps, ['max']);
  });

  testWidgets('plain model keeps Low / Medium / High', (tester) async {
    final taps = <String>[];
    await pumpChips(
      tester,
      value: 'medium',
      modelId: 'acme/gpt-lite',
      taps: taps,
    );

    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Max'), findsNothing);

    await tester.tap(find.text('Low'));
    await tester.pump();
    expect(taps, ['low']);
  });

  testWidgets('mandatory model locks Off and still shows chips', (tester) async {
    rememberReasoningProfileFromCatalog('x-ai/grok-4.6', {
      'supported_efforts': ['xhigh', 'high', 'medium', 'low'],
      'mandatory': true,
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThinkingSettingsBlock(
            enabled: false,
            onEnabledChanged: _ignoreBool,
            effort: 'medium',
            onEffortChanged: _ignoreString,
            modelId: 'x-ai/grok-4.6',
          ),
        ),
      ),
    );

    // Off lives in the level row now; a mandatory model cannot pick it.
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Off'), findsOneWidget);
    expect(find.textContaining('always thinks'), findsWidgets);
    expect(find.text('Extra high'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
  });
}

void _ignoreBool(bool _) {}
void _ignoreString(String _) {}
