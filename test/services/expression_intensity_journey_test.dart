// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

void main() {
  test(
    'intensity changes submitted wording, preserves seed and noise, and protects custom prompts',
    () async {
      for (final edit in [false, true]) {
        final prompts = <String>[];
        final seeds = <int>[];
        final strengths = <double>[];
        Completer<Uint8List?>? held;
        final s = ExpressionPackSession(
          emotions: ['anger', 'joy'],
          basePrompt: 'portrait',
          negativePrompt: '',
          denoise: 0.7,
          seed: 42,
          editMode: edit,
          intensity: ExpressionIntensity.subtle,
          promptRules: ExpressionPromptRules(
            prefix: 'before',
            suffix: 'after',
            replacements: [
              ExpressionPromptReplacement(
                find: 'gently tightened lips',
                replace: 'slightly pressed lips',
              ),
            ],
          ),
          generate:
              ({
                required prompt,
                required negativePrompt,
                required seed,
                required denoise,
              }) async {
                prompts.add(prompt);
                seeds.add(seed);
                strengths.add(denoise);
                return held?.future ?? Uint8List.fromList([1]);
              },
        );
        expect(s.effectivePromptFor(0), contains('slightly pressed lips'));
        final preview = s.effectivePromptFor(0);
        await s.run();
        expect(prompts.first, preview);
        expect(prompts.first, isNot(contains('furious')));
        expect(prompts.first, startsWith('before'));
        expect(prompts.first, endsWith('after'));
        final bytes = s.slots.first.bytes;
        expect(s.updateIntensity(ExpressionIntensity.strong), isTrue);
        expect(s.slots.first.bytes, same(bytes));
        await s.reroll(0);
        expect(prompts.last, contains('deeply furrowed brows'));
        await s.reroll(0, intensityOverride: ExpressionIntensity.clear);
        expect(prompts.last, contains('moderately narrowed eyes'));
        s.updateIntensity(ExpressionIntensity.subtle);
        await s.reroll(0);
        expect(prompts.last, contains('moderately narrowed eyes'));
        await s.reroll(0, followPackIntensity: true);
        expect(s.slots.first.intensityOverride, isNull);
        expect(prompts.last, contains('slightly pressed lips'));
        await s.reroll(0, promptOverride: 'my exact wording');
        await s.reroll(0, intensityOverride: ExpressionIntensity.strong);
        expect(prompts.last, 'my exact wording');
        await s.reroll(
          0,
          intensityOverride: ExpressionIntensity.subtle,
          useIntensityPrompt: true,
        );
        expect(prompts.last, contains('slightly pressed lips'));
        expect(s.slots.first.customPrompt, isNull);
        expect(seeds, everyElement(42));
        expect(strengths, everyElement(0.7));
        held = Completer<Uint8List?>();
        final work = s.reroll(0);
        expect(s.updateIntensity(ExpressionIntensity.strong), isFalse);
        held.complete(Uint8List.fromList([2]));
        await work;
        s.dispose();
        expect(s.updateIntensity(ExpressionIntensity.strong), isFalse);
      }
    },
  );
  test(
    'every expression has complete intensity geometry and old wording remains the default',
    () {
      for (final emotion in kFullExpressionSet) {
        for (final level in [
          ExpressionIntensity.subtle,
          ExpressionIntensity.clear,
          ExpressionIntensity.strong,
        ]) {
          expect(expressionIntensityDescription(emotion, level), isNotEmpty);
        }
        expect(
          originalExpressionPrompt(
            emotion: emotion,
            basePrompt: 'portrait',
            editMode: false,
          ),
          '${kExpressionModifiers[emotion]}, portrait',
        );
      }
      expect(() => ExpressionIntensity.parse('extreme'), throwsFormatException);
      expect(() => ExpressionIntensity.parse(1), throwsFormatException);
    },
  );
}
