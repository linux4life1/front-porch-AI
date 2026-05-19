// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

void main() {
  group('EmotionLabels', () {
test('all labels count is 30', () {
  expect(EmotionLabels.all.length, equals(30));
});

    test('all labels have emoji mappings', () {
      for (final label in EmotionLabels.all) {
        expect(
          EmotionLabels.emoji.containsKey(label),
          isTrue,
          reason: 'Label "$label" should have an emoji mapping',
        );
      }
    });

    test('emoji map contains all labels', () {
      expect(EmotionLabels.emoji.length, greaterThanOrEqualTo(28));
    });
  });

  group('EmotionLabels.nuancedToStandard', () {
    test('maps elated to joy', () {
      expect(EmotionLabels.nuancedToStandard['elated'], equals('joy'));
    });

    test('maps starstruck to love', () {
      expect(EmotionLabels.nuancedToStandard['starstruck'], equals('love'));
    });

    test('maps wistful to sadness', () {
      expect(EmotionLabels.nuancedToStandard['wistful'], equals('sadness'));
    });

    test('maps flustered to embarrassment', () {
      expect(
        EmotionLabels.nuancedToStandard['flustered'],
        equals('embarrassment'),
      );
    });

    test('maps prickly to anger', () {
      expect(EmotionLabels.nuancedToStandard['prickly'], equals('anger'));
    });

    test('maps guarded to neutral', () {
      expect(EmotionLabels.nuancedToStandard['guarded'], equals('neutral'));
    });

    test('maps smitten to love', () {
      expect(EmotionLabels.nuancedToStandard['smitten'], equals('love'));
    });

    test('maps ecstatic to joy', () {
      expect(EmotionLabels.nuancedToStandard['ecstatic'], equals('joy'));
    });

    test('maps heartbroken to grief', () {
      expect(
        EmotionLabels.nuancedToStandard['heartbroken'],
        equals('grief'),
      );
    });

    test('maps suspicious to confusion', () {
      expect(
        EmotionLabels.nuancedToStandard['suspicious'],
        equals('confusion'),
      );
    });

    test('maps determined to optimism', () {
      expect(
        EmotionLabels.nuancedToStandard['determined'],
        equals('optimism'),
      );
    });

    test('maps vulnerable to fear', () {
      expect(EmotionLabels.nuancedToStandard['vulnerable'], equals('fear'));
    });

    test('maps flirtatious to desire', () {
      expect(
        EmotionLabels.nuancedToStandard['flirtatious'],
        equals('desire'),
      );
    });

    test('maps protective to caring', () {
      expect(
        EmotionLabels.nuancedToStandard['protective'],
        equals('caring'),
      );
    });

    test('maps bittersweet to sadness', () {
      expect(
        EmotionLabels.nuancedToStandard['bittersweet'],
        equals('sadness'),
      );
    });

    test('mapping has no duplicate keys', () {
      final keys = EmotionLabels.nuancedToStandard.keys.toList();
      final uniqueKeys = keys.toSet();
      expect(
        uniqueKeys.length,
        equals(keys.length),
        reason: 'Mapping should not have duplicate keys',
      );
    });

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
        expect(prompt.contains(label), isTrue,
            reason: 'Prompt should contain label "$label"');
      }
    });
  });
}
