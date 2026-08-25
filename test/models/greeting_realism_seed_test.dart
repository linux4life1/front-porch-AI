// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-alternate-greeting Realism/Needs overlays. Proven red first: before
// greetingOverlayAt / resolveGreetingOpening existed, an angry alt inherited
// the friend first_mes seed (or fired reading-the-room and never restored).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

void main() {
  final angry = GreetingRealismSeed(
    characterEmotion: 'furious',
    emotionIntensity: 'strong',
    shortTermBond: -40,
    trustLevel: -20,
    timeOfDay: 'night',
    needsBaselineHunger: 30,
  );

  test(
    'overlay index 0 is always the card (first_mes), not greeting_seeds[0]',
    () {
      expect(
        greetingOverlayAt([angry], 0),
        isNull,
        reason: 'first_mes keeps using card-level realism_engine fields',
      );
      expect(greetingOverlayAt([angry], 1), angry);
    },
  );

  test(
    'a missing alt slot is unauthored (read-the-room); {} is authored inherit',
    () {
      expect(
        greetingHasAuthoredSeed(
          hasCardExtensions: true,
          seeds: const [null],
          greetingIndex: 1,
        ),
        isFalse,
      );
      expect(
        greetingHasAuthoredSeed(
          hasCardExtensions: true,
          seeds: [const GreetingRealismSeed()],
          greetingIndex: 1,
        ),
        isTrue,
      );
    },
  );

  test('merge overlays sparse fields onto the card base', () {
    const base = GreetingOpeningBase(
      shortTermBond: 20,
      characterEmotion: 'warm',
      emotionIntensity: 'mild',
      timeOfDay: 'morning',
      needsBaselineHunger: 80,
    );
    final resolved = resolveGreetingOpening(base, angry);
    expect(resolved.characterEmotion, 'furious');
    expect(resolved.emotionIntensity, 'strong');
    expect(resolved.shortTermBond, -40);
    expect(resolved.trustLevel, -20);
    expect(resolved.timeOfDay, 'night');
    expect(resolved.needsBaselineHunger, 30);
    expect(
      resolved.needsBaselineBladder,
      80,
      reason: 'unmentioned needs inherit',
    );
    expect(resolved.longTermBond, 0, reason: 'unmentioned bond inherits');
  });

  test(
    'swiping back to 0 is resolve(base, null) — friend mood, not leftover fury',
    () {
      const base = GreetingOpeningBase(
        characterEmotion: 'warm',
        shortTermBond: 20,
      );
      final back = resolveGreetingOpening(base, greetingOverlayAt([angry], 0));
      expect(back.characterEmotion, 'warm');
      expect(back.shortTermBond, 20);
    },
  );

  test('card JSON round-trips greeting_seeds including a null hole', () {
    final ext = FrontPorchExtensions(
      characterEmotion: 'warm',
      greetingSeeds: [angry, null, const GreetingRealismSeed()],
    );
    final restored = FrontPorchExtensions.fromJson(ext.toJson());
    expect(restored.greetingSeeds, hasLength(3));
    expect(restored.greetingSeeds[0]!.characterEmotion, 'furious');
    expect(restored.greetingSeeds[1], isNull);
    expect(restored.greetingSeeds[2], isNotNull);
    expect(restored.greetingSeeds[2]!.isEmpty, isTrue);
  });

  test('recoverGreetingIndex prefers stamped metadata then text match', () {
    expect(
      recoverGreetingIndex(
        resolvedGreetings: ['hi', 'hey', 'yo'],
        currentText: 'hey',
        storedIndex: 2,
      ),
      2,
    );
    expect(
      recoverGreetingIndex(
        resolvedGreetings: ['hi', 'hey', 'yo'],
        currentText: 'hey',
        storedIndex: null,
      ),
      1,
    );
  });

  test(
    'a web save that never mentions greetingSeeds keeps the base overlays',
    () {
      final seeded = FrontPorchExtensions(greetingSeeds: [angry]);
      final back = frontPorchFromFields(const {
        'realismEnabled': true,
        'trustLevel': 5,
      }, base: seeded);
      expect(back.greetingSeeds, hasLength(1));
      expect(back.greetingSeeds.first!.characterEmotion, 'furious');
      expect(back.trustLevel, 5);
    },
  );

  test('web round-trip of greetingSeeds is lossless', () {
    final original = FrontPorchExtensions(greetingSeeds: [angry]);
    final back = frontPorchFromFields(frontPorchToJson(original));
    expect(back.greetingSeeds.first!.characterEmotion, 'furious');
    expect(back.greetingSeeds.first!.shortTermBond, -40);
    expect(back.greetingSeeds.first!.needsBaselineHunger, 30);
  });

  test('empty overlay inherits every card field including wardrobe', () {
    const base = GreetingOpeningBase(
      characterEmotion: 'warm',
      emotionIntensity: 'mild',
      shortTermBond: 20,
      trustLevel: 10,
      timeOfDay: 'morning',
      needsBaselineHunger: 80,
      inventory: {
        'worn': [
          {'name': 'flour-dusted apron'},
        ],
      },
    );
    final resolved = resolveGreetingOpening(base, const GreetingRealismSeed());
    expect(resolved.characterEmotion, 'warm');
    expect(resolved.emotionIntensity, 'mild');
    expect(resolved.shortTermBond, 20);
    expect(resolved.trustLevel, 10);
    expect(resolved.timeOfDay, 'morning');
    expect(resolved.needsBaselineHunger, 80);
    expect(resolved.inventory, base.inventory);
  });
}
