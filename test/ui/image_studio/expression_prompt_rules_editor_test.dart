// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/image_studio/expression_pack_widgets.dart';

void main() {
  testWidgets(
    'local use, explicit global save, reset and ordering update effective previews',
    (tester) async {
      var defaults = ExpressionPromptRules(prefix: 'global');
      var current = ExpressionPromptRules(
        replacements: [
          ExpressionPromptReplacement(find: 'one', replace: 'two'),
          ExpressionPromptReplacement(find: 'two', replace: 'three'),
        ],
      );
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await showExpressionPromptRulesEditor(
                    context,
                    rules: current,
                    globalDefaults: () => defaults,
                    saveDefaults: (rules) async {
                      defaults = rules;
                      saves++;
                    },
                    originals: {'joy': 'one portrait'},
                  );
                  if (result != null) current = result;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('joy'));
      await tester.pumpAndSettle();
      expect(find.text('three portrait'), findsOneWidget);
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pumpAndSettle();
      expect(find.text('two portrait'), findsOneWidget);
      await tester.tap(find.text('Use for this pack'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(current.apply('one portrait'), 'two portrait');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to global defaults'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Text before each prompt'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save as global defaults'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(defaults.prefix, 'global');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(current.apply('one portrait'), 'two portrait');
    },
  );
  testWidgets(
    'expanding replacements surface validation and disable using rules',
    (tester) async {
      final rules = ExpressionPromptRules(
        replacements: List.generate(
          32,
          (_) => ExpressionPromptReplacement(find: 'a', replace: 'aa'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExpressionPromptRulesEditor(
            rules: rules,
            globalDefaults: () => ExpressionPromptRules(),
            saveDefaults: (_) async {},
            originals: {'joy': 'a'},
          ),
        ),
      );
      expect(
        find.text('The effective prompt must be at most 16384 characters.'),
        findsOneWidget,
      );
      final use = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Use for this pack'),
      );
      expect(use.onPressed, isNull);
    },
  );
  testWidgets(
    'custom expression previews stay exact through actual dialog helper',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showExpressionPromptRulesEditor(
                  context,
                  rules: ExpressionPromptRules(prefix: 'pack before'),
                  globalDefaults: () => ExpressionPromptRules(),
                  saveDefaults: (_) async {},
                  originals: {'joy': 'original'},
                  previewPrompt: (emotion, rules) =>
                      'single expression wording',
                ),
                child: const Text('Open preview'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('joy'));
      await tester.pumpAndSettle();
      expect(find.text('single expression wording'), findsOneWidget);
      expect(find.text('pack before original'), findsNothing);
    },
  );
  testWidgets(
    'deleting an expanding rule clears validation and re-enables local use',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExpressionPromptRulesEditor(
            rules: ExpressionPromptRules(
              replacements: [
                ExpressionPromptReplacement(
                  find: 'a',
                  replace: List.filled(2048, 'a').join(),
                ),
              ],
            ),
            globalDefaults: () => ExpressionPromptRules(),
            saveDefaults: (_) async {},
            originals: {'joy': 'aaaaaaaaa'},
          ),
        ),
      );
      expect(
        find.text('The effective prompt must be at most 16384 characters.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('Delete replacement'));
      await tester.tap(find.byTooltip('Delete replacement'));
      await tester.pumpAndSettle();
      expect(
        find.text('The effective prompt must be at most 16384 characters.'),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use for this pack'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
