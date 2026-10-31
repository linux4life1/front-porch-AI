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

  // The new-group wizard and Edit group used to save Long-Term Bond into
  // trust. These are what their sliders now show and write.
  group('bondSlidersFromMemberSeed', () {
    test('Long-Term Bond reads longTermScore and Trust Level reads trust', () {
      final b = bondSlidersFromMemberSeed({
        'affection': 70,
        'longTermScore': 250,
        'trust': 60,
      });
      expect((b.shortTerm, b.longTerm, b.trust), (70, 250, 60));
    });

    test('an unset Long-Term Bond follows Short-Term Bond, as the engine '
        'does', () {
      final b = bondSlidersFromMemberSeed({'affection': -200, 'trust': 40});
      expect((b.longTerm, b.trust), (-200, 40));
    });

    test('only a trust past ±100 with no longTermScore reads as the '
        'mix-up', () {
      expect(bondSlidersFromMemberSeed({'trust': 100}).trust, 100);
      expect(bondSlidersFromMemberSeed({'trust': 101}).longTerm, 101);
      final both = bondSlidersFromMemberSeed({
        'longTermScore': 20,
        'trust': 250,
      });
      expect((both.longTerm, both.trust), (20, 100));
    });

    test('a seed the old editors left with Long-Term Bond in trust shows it '
        'as Long-Term Bond and the neutral trust', () {
      final b = bondSlidersFromMemberSeed({'affection': 35, 'trust': 250});
      expect((b.longTerm, b.trust), (250, 50));
    });
  });

  group('bondSliderEdit', () {
    test('each slider writes its own key and nothing else', () {
      final seed = {'affection': 35, 'trust': 40};
      expect(bondSliderEdit(seed, shortTerm: 90), {'affection': 90});
      expect(bondSliderEdit(seed, longTerm: 250), {'longTermScore': 250});
      expect(bondSliderEdit(seed, trust: -50), {'trust': -50});
    });

    test('on a seed with Long-Term Bond in trust, a move writes all three as '
        'shown', () {
      final seed = {'affection': 35, 'trust': 250};
      expect(bondSliderEdit(seed, trust: -50), {
        'affection': 35,
        'longTermScore': 250,
        'trust': -50,
      });
      expect(bondSliderEdit(seed, longTerm: 100), {
        'affection': 35,
        'longTermScore': 100,
        'trust': 50,
      });
    });
  });
}
