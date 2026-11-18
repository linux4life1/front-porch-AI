// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

void main() {
  // The full label set, its emoji/ring-color detail and the nuanced->standard
  // map are frozen by test/golden/emotion/emotion_labels_golden_test.dart, so
  // the per-entry "maps X to Y" checks and the set/emoji/count checks are not
  // repeated here. Only the invariants that golden cannot assert live below.
  group('EmotionLabels.nuancedToStandard', () {
    test('all mapped values are valid standard labels', () {
      for (final value in EmotionLabels.nuancedToStandard.values) {
        expect(
          EmotionLabels.all.contains(value),
          isTrue,
          reason: 'Mapped value "$value" should be a valid standard label',
        );
      }
    });
  });

  group('EmotionLabels.buildReclassifyPrompt', () {
    test('generates valid prompt for unknown emotion', () {
      final prompt = EmotionLabels.buildReclassifyPrompt(' derpstruck');
      expect(prompt.contains('derpstruck'), isTrue);
      expect(prompt.contains('admiration'), isTrue);
      expect(prompt.contains('joy'), isTrue);
      expect(prompt.contains('sadness'), isTrue);
    });

    test('prompt includes all standard labels', () {
      final prompt = EmotionLabels.buildReclassifyPrompt('unknown');
      for (final label in EmotionLabels.all) {
        expect(
          prompt.contains(label),
          isTrue,
          reason: 'Prompt should contain label "$label"',
        );
      }
    });
  });
}
