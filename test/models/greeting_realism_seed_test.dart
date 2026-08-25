// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-alternate-greeting Realism/Needs overlays. Proven red first: before
// greetingOverlayAt / resolveGreetingOpening existed, an angry alt inherited
// the friend first_mes seed (or fired reading-the-room and never restored).

import 'dart:io';

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

  test('compactGreetingPairs drops empty greet rows with their seed slots', () {
    final furious = GreetingRealismSeed(characterEmotion: 'furious');
    // Add / blank / Add / "Get out." / seed furious
    final paired = compactGreetingPairs(['', 'Get out.'], [null, furious]);
    expect(paired.greetings, ['Get out.']);
    expect(paired.seeds, hasLength(1));
    expect(
      paired.seeds.first!.characterEmotion,
      'furious',
      reason: 'furious must stay on Get out., not shift onto the blank row',
    );
  });

  test('leftover furious on a blank greet row does not land on Get out', () {
    final furious = GreetingRealismSeed(characterEmotion: 'furious');
    // Dirty ['', 'Get out.'] + [furious]: blank row drops WITH its seed slot.
    final paired = compactGreetingPairs(['', 'Get out.'], [furious]);
    expect(paired.greetings, ['Get out.']);
    expect(
      paired.seeds,
      isEmpty,
      reason:
          'furious sat on the blank; unpaired prefix-align would load it onto Get out',
    );
  });

  test(
    'prefix-align after dropping empty greets is the bug compactGreetingPairs fixes',
    () {
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      final greets = ['', 'Get out.'];
      final alts = [
        for (final g in greets)
          if (g.trim().isNotEmpty) g,
      ];
      final wrong = alignGreetingSeeds([null, furious], alts.length);
      expect(
        wrong.first,
        isNull,
        reason: 'old prefix-align drops furious; compactGreetingPairs must not',
      );
    },
  );

  test(
    'a blank middle row does not pair its seed with neighboring Get out',
    () {
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      final paired = compactGreetingPairs(
        ['Come in.', '', 'Get out.'],
        [null, GreetingRealismSeed(characterEmotion: 'stolen'), furious],
      );
      expect(paired.greetings, ['Come in.', 'Get out.']);
      expect(paired.seeds, hasLength(2));
      expect(paired.seeds[0], isNull);
      expect(
        paired.seeds[1]!.characterEmotion,
        'furious',
        reason: 'blank row must drop with its slot; furious stays on Get out.',
      );
    },
  );

  test(
    'parseGroupAlternateGreetings and parseGroupGreetingSeeds share compactGreetingPairs',
    () {
      final blobs = File(
        'lib/utils/group_realism_blobs.dart',
      ).readAsStringSync();
      final alt = RegExp(
        r'List<String> parseGroupAlternateGreetings\(String defaultMemberJson\) \{([^}]+)\}',
      ).firstMatch(blobs);
      final seeds = RegExp(
        r'List<GreetingRealismSeed\?> parseGroupGreetingSeeds\(String defaultMemberJson\) \{([^}]+)\}',
      ).firstMatch(blobs);
      expect(alt, isNotNull);
      expect(seeds, isNotNull);
      expect(
        alt!.group(1),
        contains('parseGroupOpeningPairs'),
        reason: 'alts must not compact greetings without the paired seed slots',
      );
      expect(
        seeds!.group(1),
        contains('parseGroupOpeningPairs'),
        reason: 'seeds must not parse greetingSeeds without the paired greets',
      );
      expect(
        blobs.contains(
          "return compactGreetingPairs(greets, parseGreetingSeeds(map['greetingSeeds']));",
        ),
        isTrue,
        reason: 'the shared helper is the compactGreetingPairs pairing',
      );

      final group = File('lib/models/group_chat.dart').readAsStringSync();
      expect(
        group.contains('compactGreetingPairs'),
        isTrue,
        reason: 'GroupChat.fromJson must use the same pairing',
      );
    },
  );

  test(
    'FrontPorchExtensions.fromJson pairs empty-greet drop with compactGreetingPairs',
    () {
      final dirty = FrontPorchExtensions.fromJson(
        {
          'realism_engine': {
            'enabled': true,
            'greeting_seeds': [
              {'character_emotion': 'furious'},
            ],
          },
        },
        alternateGreetings: ['', 'Get out.'],
      );
      expect(
        dirty.greetingSeeds,
        isEmpty,
        reason: "['', 'Get out.']+[furious] must not load furious onto Get out",
      );
      expect(greetingOverlayAt(dirty.greetingSeeds, 1), isNull);

      final kept = FrontPorchExtensions.fromJson(
        {
          'realism_engine': {
            'enabled': true,
            'greeting_seeds': [
              null,
              {'character_emotion': 'furious'},
            ],
          },
        },
        alternateGreetings: ['', 'Get out.'],
      );
      expect(kept.greetingSeeds, hasLength(1));
      expect(kept.greetingSeeds.first!.characterEmotion, 'furious');

      // Extra: fromJson must call compactGreetingPairs when alts are present.
      final fromJsonSrc = File('lib/models/character_card.dart').readAsStringSync();
      expect(
        fromJsonSrc.contains(
          'return compactGreetingPairs(alternateGreetings, parsed).seeds;',
        ),
        isTrue,
        reason: '1:1 fromJson pairs through compactGreetingPairs, not prefix-align',
      );
    },
  );

  test(
    'toJson/fromJson without alts keeps sparse seed holes',
    () {
      final ext = FrontPorchExtensions(
        greetingSeeds: [
          null,
          GreetingRealismSeed(characterEmotion: 'furious'),
          null,
          const GreetingRealismSeed(),
        ],
      );
      final json = ext.toJson();
      final seedsJson =
          (json['realism_engine'] as Map)['greeting_seeds'] as List;
      expect(
        seedsJson,
        hasLength(4),
        reason: 'toJson must keep internal holes; only trailing nulls compact',
      );
      expect(seedsJson[0], isNull);
      expect(seedsJson[2], isNull);

      final restored = FrontPorchExtensions.fromJson(json);
      expect(
        restored.greetingSeeds,
        hasLength(4),
        reason: 'no-alts fromJson must not compact-pair holes away',
      );
      expect(restored.greetingSeeds[0], isNull);
      expect(restored.greetingSeeds[1]!.characterEmotion, 'furious');
      expect(restored.greetingSeeds[2], isNull);
      expect(restored.greetingSeeds[3], isNotNull);
      expect(restored.greetingSeeds[3]!.isEmpty, isTrue);

      final emptyAlts = FrontPorchExtensions.fromJson(
        json,
        alternateGreetings: const [],
      );
      expect(
        emptyAlts.greetingSeeds,
        hasLength(4),
        reason: 'explicit empty alts must still preserve sparse seed holes',
      );
      expect(emptyAlts.greetingSeeds[0], isNull);
      expect(emptyAlts.greetingSeeds[1]!.characterEmotion, 'furious');
      expect(greetingOverlayAt(emptyAlts.greetingSeeds, 1), isNull);
      expect(
        greetingOverlayAt(emptyAlts.greetingSeeds, 2)!.characterEmotion,
        'furious',
      );
    },
  );

  test(
    'characters.md pins first_mes, skip-RtR, {} vs null, swipe-0, groups 1:1',
    () {
      final md = File('docs/characters.md').readAsStringSync();
      expect(md.contains('first_mes'), isTrue);
      expect(md.contains('Reads the Room'), isTrue);
      expect(md.contains('including empty `{}`'), isTrue);
      expect(md.contains('Swipe 0'), isTrue);
      expect(md.contains('Groups match 1:1'), isTrue);
      expect(
        md.contains('must not write `{}` just because the seed toggle is on'),
        isTrue,
      );
    },
  );
}
