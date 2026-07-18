// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image_prompt/expression_prompts.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

void main() {
  group('Expression pack prompt data', () {
    test('every curated-set member is a real EmotionLabels.all label', () {
      for (final e in kCuratedExpressionSet) {
        expect(
          EmotionLabels.all,
          contains(e),
          reason: 'curated label "$e" is not in EmotionLabels.all',
        );
      }
    });

    test('every full-set member is a real EmotionLabels.all label', () {
      for (final e in kFullExpressionSet) {
        expect(
          EmotionLabels.all,
          contains(e),
          reason: 'full-set label "$e" is not in EmotionLabels.all',
        );
      }
    });

    test('curated set is a subset of the full set', () {
      for (final e in kCuratedExpressionSet) {
        expect(
          kFullExpressionSet,
          contains(e),
          reason: 'curated label "$e" missing from the full set',
        );
      }
    });

    test('full set has exactly 28 unique entries', () {
      expect(kFullExpressionSet, hasLength(28));
      expect(kFullExpressionSet.toSet(), hasLength(28));
    });

    test('full set excludes affection and anticipation (ONNX-unreachable)', () {
      expect(kFullExpressionSet, isNot(contains('affection')));
      expect(kFullExpressionSet, isNot(contains('anticipation')));
    });

    test('kExpressionModifiers keys match the full set exactly', () {
      expect(
        kExpressionModifiers.keys.toSet(),
        equals(kFullExpressionSet.toSet()),
      );
    });

    test('every modifier phrase is non-empty', () {
      kExpressionModifiers.forEach((emotion, phrase) {
        expect(
          phrase.trim(),
          isNotEmpty,
          reason: 'modifier for "$emotion" is empty',
        );
      });
    });

    test('framing suffix is non-empty', () {
      expect(kExpressionFraming.trim(), isNotEmpty);
    });
  });

  test('kExpressionNegatives covers the full set with non-empty cues', () {
    expect(
      kExpressionNegatives.keys.toSet(),
      kFullExpressionSet.toSet(),
      reason: 'every pack emotion needs its counter-cues (even if a backend '
          'ignores negatives)',
    );
    for (final entry in kExpressionNegatives.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
    }
  });

  group('expressionEditInstruction (edit-path prompt)', () {
    test('reuses the geometry description and adds an identity-preserving '
        'instruction, for every full-set emotion', () {
      for (final e in kFullExpressionSet) {
        final ins = expressionEditInstruction(e);
        // Derived from the ONE modifier table (no drift between the two paths).
        expect(ins, contains(kExpressionModifiers[e]!), reason: e);
        expect(ins, contains('Change only the facial expression'), reason: e);
        // Keeps identity/composition (the reference image supplies those).
        expect(ins.toLowerCase(), contains('keep the same person'), reason: e);
      }
    });

    test('an unknown emotion falls back to the label itself', () {
      final ins = expressionEditInstruction('smug');
      expect(ins, contains('smug'));
    });
  });
}
