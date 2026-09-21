// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TWO BUGS IN THE GROUP SETTINGS → REALISM PER-MEMBER BASELINE EDITOR.
//
// 1. It wrote the authored Bond/Trust/Emotion into the group's per-member seed
//    blob under CARD-EXT field names (shortTermBond/longTermBond/trustLevel/
//    characterEmotion). The runtime reads that blob through
//    parseGroupRealismSeeds → GroupMemberRealism, which knows only the ENGINE
//    names (affection/longTermScore/trust/emotion/emotionIntensity) and passes
//    everything else through untouched. Four of the five sliders were therefore
//    silent no-ops: every new chat in the group re-seeded from the wizard's
//    original values while the authored numbers sat in the DB as dead keys.
//
// 2. Long-Term Bond reloaded as the Short-Term value, because it is read out of
//    ChatService.getBaselineSeedForGroupCharacter — whose return literal has no
//    'longTermScore' key at all — and fell back to 'affection'. The next drag of
//    any other slider then wrote that fallback over the stored long-term
//    baseline, destroying it.
//
// The tab itself has no unit seam: every ChatService door it uses is an
// EXTENSION member, so it resolves on the static type and runs its real body
// (reaching private ChatService fields) even against a test double, and a real
// ChatService cannot be driven under testWidgets (drift wall-hangs there — see
// the note in edit_group_page_interaction_test.dart). So the two halves that
// carried the bugs are pure functions, pinned here, plus a source pin that the
// tab still routes through them.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';

void main() {
  group('applyBaselineToMemberSeed', () {
    test('writes the engine key names, not the card-ext ones', () {
      final seed = applyBaselineToMemberSeed(
        <String, dynamic>{},
        affection: 200,
        longTermScore: 250,
        trust: -50,
        emotion: 'wary',
        emotionIntensity: 'intense',
      );

      // Exactly what GroupMemberRealism reads back.
      expect(seed[GroupRealismKeys.affection], 200);
      expect(seed[GroupRealismKeys.longTermScore], 250);
      expect(seed[GroupRealismKeys.trust], -50);
      expect(seed[GroupRealismKeys.emotion], 'wary');
      expect(seed[GroupRealismKeys.emotionIntensity], 'intense');

      // And it really is what the runtime wrapper exposes.
      final member = GroupMemberRealism.fromJson(seed);
      expect(member.affection, 200);
      expect(member.longTermScore, 250);
      expect(member.trust, -50);
      expect(member.emotion, 'wary');
      expect(member.emotionIntensity, 'intense');
    });

    test('strips the dead card-ext copies an earlier build left behind', () {
      final seed = applyBaselineToMemberSeed(
        <String, dynamic>{
          'shortTermBond': 10,
          'longTermBond': 11,
          'trustLevel': 12,
          'characterEmotion': 'happy',
          'needs': {'hunger': 70},
        },
        affection: 35,
        longTermScore: 40,
        trust: 20,
        emotion: 'neutral',
        emotionIntensity: 'mild',
      );

      for (final dead in legacyCardExtSeedKeys) {
        expect(seed.containsKey(dead), isFalse, reason: '$dead must be gone');
      }
      // Unrelated seed content is never touched.
      expect(seed['needs'], {'hunger': 70});
    });
  });

  group('longTermBondFromSeeds', () {
    test('takes the engine seed when the baseline blob cannot answer', () {
      // Exactly the shape getBaselineSeedForGroupCharacter returns: six keys,
      // none of them longTermScore.
      const baseline = {
        'affection': 50,
        'trust': 40,
        'emotion': 'neutral',
        'emotionIntensity': 'moderate',
        'timeOfDay': 'morning',
        'dayCount': 1,
      };

      expect(
        longTermBondFromSeeds(
          baselineSeed: baseline,
          perCharSeed: const {'affection': 50, 'longTermScore': 250},
        ),
        250,
        reason:
            'reloading 50 here is the data-loss bug: the next slider drag '
            'writes the displayed value back over the stored 250',
      );
    });

    test(
      'recovers a value a previous build stored under the card-ext name',
      () {
        expect(
          longTermBondFromSeeds(
            perCharSeed: const {'affection': 50, 'longTermBond': 180},
          ),
          180,
        );
      },
    );

    test('prefers the baseline blob when it does carry the key', () {
      expect(
        longTermBondFromSeeds(
          baselineSeed: const {'longTermScore': 120},
          perCharSeed: const {'longTermScore': 90, 'longTermBond': 70},
        ),
        120,
      );
    });

    test('null when nothing was ever authored (caller falls back to bond)', () {
      expect(
        longTermBondFromSeeds(
          baselineSeed: const {'affection': 35, 'trust': 40},
          perCharSeed: const {'affection': 35, 'trust': 40},
        ),
        isNull,
      );
      expect(longTermBondFromSeeds(), isNull);
    });

    test('a non-numeric value reads as absent rather than throwing', () {
      expect(
        longTermBondFromSeeds(perCharSeed: const {'longTermScore': 'oops'}),
        isNull,
      );
    });
  });

  group('bondBaselineFromSeeds', () {
    test('the three sliders load from the three engine keys', () {
      final bond = bondBaselineFromSeeds(
        baselineSeed: const {'affection': 200, 'trust': -60},
        perCharSeed: const {'longTermScore': 250},
      );
      expect(bond.shortTerm, 200);
      expect(bond.longTerm, 250);
      expect(bond.trust, -60);
    });

    test('long-term falls back to bond when nothing was authored', () {
      final bond = bondBaselineFromSeeds(
        baselineSeed: const {'affection': 35, 'trust': 40},
      );
      expect(bond.longTerm, 35);
      expect(bond.trust, 40);
    });

    test(
      'a bond number stranded in trust is moved back, not shown as trust',
      () {
        // A group edited by the pre-fix editor, which saved Long-Term Bond INTO
        // 'trust'. Unrepaired, 300 reaches a Slider declared min -100 / max 100
        // and takes the whole dialog down.
        final bond = bondBaselineFromSeeds(
          baselineSeed: const {'affection': 120, 'trust': 300},
        );
        expect(bond.longTerm, 300);
        expect(bond.trust, 50, reason: 'no real trust value exists to recover');
      },
    );

    test('everything is clamped to its slider range', () {
      final bond = bondBaselineFromSeeds(
        baselineSeed: const {'affection': 9999, 'trust': -90},
        perCharSeed: const {'longTermScore': -9999},
      );
      expect(bond.shortTerm, 300);
      expect(bond.longTerm, -300);
      expect(bond.trust, -90);
    });
  });
}
