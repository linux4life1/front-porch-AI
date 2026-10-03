// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/storage/settings/expression_settings.dart';

class _RefusingPreferences implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pack submits ordered rules, keeps overrides, preserves images and rejects edits during flight',
    () async {
      final rows = [
        ExpressionPromptReplacement(find: 'portrait', replace: 'painting'),
        ExpressionPromptReplacement(find: 'painting', replace: r'$literal'),
      ];
      final defaults = ExpressionPromptRules(
        prefix: 'before',
        suffix: 'after',
        replacements: rows,
      );
      rows.clear();
      final submitted = <String>[];
      final negative = <String>[];
      Completer<Uint8List?>? held;
      final s = ExpressionPackSession(
        emotions: ['joy', 'sadness'],
        basePrompt: 'portrait',
        negativePrompt: 'portrait',
        denoise: 0.7,
        promptRules: defaults,
        generate:
            ({
              required String prompt,
              required String negativePrompt,
              required int seed,
              required double denoise,
            }) async {
              submitted.add(prompt);
              negative.add(negativePrompt);
              return held?.future ?? Uint8List.fromList([1]);
            },
      );
      expect(defaults.replacements, hasLength(2));
      expect(() => defaults.replacements.clear(), throwsUnsupportedError);
      await s.run();
      expect(
        submitted.first,
        'before ${kExpressionModifiers['joy']}, \$literal after',
      );
      expect(negative.first, 'portrait, ${kExpressionNegatives['joy']}');
      final bytes = s.slots.first.bytes;
      expect(s.updatePromptRules(ExpressionPromptRules(prefix: 'new')), isTrue);
      expect(s.slots.first.bytes, same(bytes));
      await s.reroll(0);
      expect(submitted.last, 'new ${kExpressionModifiers['joy']}, portrait');
      await s.reroll(0, promptOverride: 'my complete portrait');
      expect(submitted.last, 'my complete portrait');
      expect(s.previewPromptFor(0, defaults), 'my complete portrait');
      s.updatePromptRules(defaults);
      await s.reroll(0);
      expect(submitted.last, 'my complete portrait');
      held = Completer<Uint8List?>();
      final running = s.reroll(1);
      expect(
        s.updatePromptRules(ExpressionPromptRules(prefix: 'forbidden')),
        isFalse,
      );
      held.complete(Uint8List.fromList([2]));
      await running;
      expect(s.promptRules.prefix, 'before');
      s.dispose();
    },
  );
  test(
    'empty rules preserve bytes and literal case-insensitive replacements have bounded expansion',
    () {
      expect(ExpressionPromptRules().apply('  unchanged\n '), '  unchanged\n ');
      expect(
        ExpressionPromptRules(
          replacements: [
            ExpressionPromptReplacement(
              find: '[a]',
              replace: r'$1',
              caseSensitive: false,
            ),
          ],
        ).apply('[A] a'),
        r'$1 a',
      );
      expect(
        () => ExpressionPromptReplacement(find: '', replace: ''),
        throwsFormatException,
      );
      final huge = ExpressionPromptRules(
        replacements: List.generate(
          32,
          (_) => ExpressionPromptReplacement(find: 'a', replace: 'aa'),
        ),
      );
      expect(() => huge.apply('a'), throwsFormatException);
    },
  );
  test(
    'defaults roundtrip with beta-aware key and malformed storage falls back to empty',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = ExpressionSettings()..initializeBase(prefs, () {});
      final saved = ExpressionPromptRules(
        prefix: 'before',
        replacements: [
          ExpressionPromptReplacement(
            find: 'one',
            replace: 'two',
            caseSensitive: false,
          ),
        ],
      );
      await settings.setExpressionPromptRules(saved);
      expect(
        jsonDecode(prefs.getString(settings.k('expression_prompt_rules'))!),
        saved.toJson(),
      );
      final loaded = ExpressionSettings()
        ..initializeBase(prefs, () {})
        ..load();
      expect(loaded.expressionPromptRules.toJson(), saved.toJson());
      await prefs.setString(settings.k('expression_prompt_rules'), '{bad');
      loaded.load();
      expect(
        loaded.expressionPromptRules.toJson(),
        ExpressionPromptRules().toJson(),
      );
    },
  );
  test(
    'saving defaults without initialized preferences reports failure and preserves memory',
    () async {
      final settings = ExpressionSettings();
      await expectLater(
        settings.setExpressionPromptRules(
          ExpressionPromptRules(prefix: 'unsaved'),
        ),
        throwsStateError,
      );
      expect(settings.expressionPromptRules.prefix, isEmpty);
    },
  );
  test(
    'failed disk write preserves prior defaults and wrong stored value type logs and falls back',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = ExpressionSettings()..initializeBase(preferences, () {});
      await settings.setExpressionPromptRules(
        ExpressionPromptRules(prefix: 'saved'),
      );
      settings.prefs = _RefusingPreferences();
      await expectLater(
        settings.setExpressionPromptRules(
          ExpressionPromptRules(prefix: 'lost'),
        ),
        throwsStateError,
      );
      expect(settings.expressionPromptRules.prefix, 'saved');
      SharedPreferences.setMockInitialValues({
        settings.k('expression_prompt_rules'): 42,
      });
      settings.initializeBase(await SharedPreferences.getInstance(), () {});
      settings.load();
      expect(settings.expressionPromptRules.prefix, isEmpty);
    },
  );
}
