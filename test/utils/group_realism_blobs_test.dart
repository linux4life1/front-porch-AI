// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

void main() {
  // A representative two-member seed set, matching the shape the group creator
  // builds in `_memberRealismSeeds`: scalars + needs map + intragroup
  // relationships (targetId -> feeling) + per-need baselines.
  Map<String, Map<String, dynamic>> sampleSeeds() => {
    'alice': {
      'affection': 75,
      'trust': 60,
      'emotion': 'affection',
      'emotionIntensity': 'strong',
      'needs': {'hunger': 80, 'social': 65},
      'relationships': {'bob': 40},
      'needsBaselineHunger': 80,
      'needsDecayHunger': 5,
    },
    'bob': {
      'affection': 35,
      'trust': 40,
      'emotion': 'neutral',
      'emotionIntensity': 'mild',
      'needs': {'hunger': 80},
      'relationships': {'alice': -20},
    },
  };

  group('buildGroupRealismBlobs — canonical group-creator contract', () {
    test('defaultMemberRealismState wraps the FULL seed under perChar[id] '
        '(what the realism engine reads)', () {
      final blobs = buildGroupRealismBlobs(
        seeds: sampleSeeds(),
        needsEnabled: true,
        timeOfDay: 'evening',
        dayCount: 3,
      );
      final dm = jsonDecode(blobs.defaultMemberJson) as Map<String, dynamic>;
      final perChar = dm['perChar'] as Map<String, dynamic>;

      expect(perChar.keys, containsAll(['alice', 'bob']));
      expect((perChar['alice'] as Map)['affection'], 75);
      expect((perChar['alice'] as Map)['trust'], 60);
      // Needs + per-need baseline/decay survive.
      expect(((perChar['alice'] as Map)['needs'] as Map)['hunger'], 80);
      expect((perChar['alice'] as Map)['needsDecayHunger'], 5);
      // Intragroup dynamics (relationships) survive — the whole point.
      expect(((perChar['alice'] as Map)['relationships'] as Map)['bob'], 40);
      expect(((perChar['bob'] as Map)['relationships'] as Map)['alice'], -20);
    });

    test('baselineRealismState is scalars-only + global time/day '
        '(no needs, no relationships)', () {
      final blobs = buildGroupRealismBlobs(
        seeds: sampleSeeds(),
        needsEnabled: true,
        timeOfDay: 'evening',
        dayCount: 3,
      );
      final base = jsonDecode(blobs.baselineJson) as Map<String, dynamic>;

      expect(base['alice'], {
        'affection': 75,
        'trust': 60,
        'emotion': 'affection',
        'emotionIntensity': 'strong',
        'timeOfDay': 'evening',
        'dayCount': 3,
      });
      expect((base['alice'] as Map).containsKey('needs'), isFalse);
      expect((base['alice'] as Map).containsKey('relationships'), isFalse);
    });

    test(
      'missing scalars fall back to the documented defaults (35/40/neutral/mild)',
      () {
        final blobs = buildGroupRealismBlobs(
          seeds: {
            'x': {'relationships': <String, int>{}},
          },
          needsEnabled: true,
          timeOfDay: 'morning',
          dayCount: 1,
        );
        final base = (jsonDecode(blobs.baselineJson) as Map)['x'] as Map;
        expect(base['affection'], 35);
        expect(base['trust'], 40);
        expect(base['emotion'], 'neutral');
        expect(base['emotionIntensity'], 'mild');
      },
    );

    test('needs disabled strips the needs map from both blobs '
        'but keeps relationships', () {
      final blobs = buildGroupRealismBlobs(
        seeds: sampleSeeds(),
        needsEnabled: false,
        timeOfDay: 'noon',
        dayCount: 1,
      );
      final perChar =
          (jsonDecode(blobs.defaultMemberJson) as Map)['perChar'] as Map;
      expect((perChar['alice'] as Map).containsKey('needs'), isFalse);
      expect(((perChar['alice'] as Map)['relationships'] as Map)['bob'], 40);
    });

    test('stripping needs does NOT mutate the caller\'s seed map', () {
      final seeds = sampleSeeds();
      buildGroupRealismBlobs(
        seeds: seeds,
        needsEnabled: false,
        timeOfDay: 'noon',
        dayCount: 1,
      );
      // The original seed still has its needs — build worked on a copy.
      expect(seeds['alice']!.containsKey('needs'), isTrue);
    });
  });

  group('parseGroupRealismSeeds — inverse (editor load)', () {
    test('round-trips: parse(build(seeds).defaultMemberJson) == seeds', () {
      final seeds = sampleSeeds();
      final blobs = buildGroupRealismBlobs(
        seeds: seeds,
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      final back = parseGroupRealismSeeds(blobs.defaultMemberJson);
      expect(back, seeds); // deep equality — lossless load↔save
    });

    test('blank / absent state yields an empty map', () {
      expect(parseGroupRealismSeeds(''), isEmpty);
      expect(parseGroupRealismSeeds('{}'), isEmpty);
      expect(parseGroupRealismSeeds('{"perChar":{}}'), isEmpty);
    });

    test('tolerates a legacy blob with no perChar wrapper', () {
      expect(parseGroupRealismSeeds('{"alice":{"affection":10}}'), isEmpty);
    });
  });

  group(
    'parseGroupTimeSeed — the fresh-session clock seed (story calendar)',
    () {
      test('alternate greetings and greeting seeds round-trip on the blob', () {
        final angry = GreetingRealismSeed(
          characterEmotion: 'furious',
          emotionIntensity: 'strong',
        );
        final blobs = buildGroupRealismBlobs(
          seeds: {'a': defaultGroupMemberRealismSeed()},
          needsEnabled: true,
          timeOfDay: 'night',
          dayCount: 2,
          alternateGreetings: ['Get out.', 'Sit down.'],
          greetingSeeds: [angry, null],
        );
        expect(parseGroupAlternateGreetings(blobs.defaultMemberJson), [
          'Get out.',
          'Sit down.',
        ]);
        final seeds = parseGroupGreetingSeeds(blobs.defaultMemberJson);
        expect(seeds.first!.characterEmotion, 'furious');
        expect(
          greetingOverlayAt(seeds, 2),
          isNull,
          reason: 'trailing null slots compact; missing = unauthored',
        );

        final patched = withGroupOpeningAlts(
          blobs.defaultMemberJson,
          alternateGreetings: ['Only one'],
          greetingSeeds: [angry],
        );
        expect(parseGroupAlternateGreetings(patched), ['Only one']);
        expect(
          parseGroupTimeSeed(patched, blobs.baselineJson)?.timeOfDay,
          'night',
        );
      });

      test(
        'dirty blob empty-greet drop is paired; prefix leftover stays off Get out',
        () {
          const prefixDirty =
              '{"alternateGreetings":["","Get out."],"greetingSeeds":[{"character_emotion":"furious"}]}';
          expect(parseGroupAlternateGreetings(prefixDirty), ['Get out.']);
          expect(
            parseGroupGreetingSeeds(prefixDirty),
            isEmpty,
            reason:
                'furious sat on the blank row; unpaired drop would load it onto Get out',
          );

          const pairedDirty =
              '{"alternateGreetings":["","Get out."],"greetingSeeds":[null,{"character_emotion":"furious"}]}';
          expect(parseGroupAlternateGreetings(pairedDirty), ['Get out.']);
          expect(
            parseGroupGreetingSeeds(pairedDirty).first!.characterEmotion,
            'furious',
            reason: 'paired slot 1 stays on Get out',
          );
        },
      );

      test(
        'GroupChat.fromJson pairs empty-greet drop with the seed index',
        () {
          final g = GroupChat.fromJson({
            'id': 'g1',
            'name': 'House',
            'first_message': 'Come in.',
            'alternate_greetings': ['', 'Get out.'],
            'greeting_seeds': [
              {'character_emotion': 'furious'},
            ],
          });
          expect(g.alternateGreetings, ['Get out.']);
          expect(
            g.greetingSeeds,
            isEmpty,
            reason: 'prefix leftover must not load furious onto Get out',
          );

          final kept = GroupChat.fromJson({
            'id': 'g2',
            'name': 'House',
            'first_message': 'Come in.',
            'alternate_greetings': ['', 'Get out.'],
            'greeting_seeds': [
              null,
              {'character_emotion': 'furious'},
            ],
          });
          expect(kept.alternateGreetings, ['Get out.']);
          expect(kept.greetingSeeds.single!.characterEmotion, 'furious');
        },
      );

      test(
        'JSON-null greet slots stay aligned then compact keeps furious on Get out',
        () {
          const blob =
              '{"alternateGreetings":[null,"Get out."],"greetingSeeds":[null,{"character_emotion":"furious"}]}';
          expect(parseGroupAlternateGreetings(blob), ['Get out.']);
          expect(
            parseGroupGreetingSeeds(blob).single!.characterEmotion,
            'furious',
            reason: 'dropping the null greet first would lose or mis-zip furious',
          );

          final g = GroupChat.fromJson({
            'id': 'g-null-slot',
            'name': 'House',
            'first_message': 'Come in.',
            'alternate_greetings': [null, 'Get out.'],
            'greeting_seeds': [
              null,
              {'character_emotion': 'furious'},
            ],
          });
          expect(g.alternateGreetings, ['Get out.']);
          expect(g.greetingSeeds.single!.characterEmotion, 'furious');
        },
      );

      test('GroupChat.toJson/fromJson round-trips greeting_seeds', () {
        final original = GroupChat(
          id: 'g-persist-seeds',
          name: 'House',
          firstMessage: 'Come in.',
          alternateGreetings: ['Get out.'],
          greetingSeeds: [
            GreetingRealismSeed(characterEmotion: 'furious'),
          ],
        );
        final json = original.toJson();
        expect(
          json.containsKey('greeting_seeds'),
          isTrue,
          reason: 'toJson used to omit greeting_seeds and lose them on reload',
        );
        final back = GroupChat.fromJson(json);
        expect(back.alternateGreetings, ['Get out.']);
        expect(back.greetingSeeds.single!.characterEmotion, 'furious');
      });

      test(
        'blank greet row does not steal furious off Get out on the blob',
        () {
          final furious = GreetingRealismSeed(characterEmotion: 'furious');
          final blobs = buildGroupRealismBlobs(
            seeds: {'a': defaultGroupMemberRealismSeed()},
            needsEnabled: true,
            timeOfDay: 'morning',
            dayCount: 1,
            alternateGreetings: ['', 'Get out.'],
            greetingSeeds: [null, furious],
          );
          expect(parseGroupAlternateGreetings(blobs.defaultMemberJson), [
            'Get out.',
          ]);
          final seeds = parseGroupGreetingSeeds(blobs.defaultMemberJson);
          expect(seeds, hasLength(1));
          expect(
            seeds.first!.characterEmotion,
            'furious',
            reason: 'compactGreetingPairs must keep furious on Get out.',
          );
        },
      );

      test(
        'reads the canonical top-level keys buildGroupRealismBlobs writes',
        () {
          final blobs = buildGroupRealismBlobs(
            seeds: sampleSeeds(),
            needsEnabled: true,
            timeOfDay: 'evening',
            dayCount: 3,
            storyStartDate: '1887-06-01',
            storyStartTime: '23:47',
          );
          final seed = parseGroupTimeSeed(
            blobs.defaultMemberJson,
            blobs.baselineJson,
          );
          expect(seed, isNotNull);
          expect(seed!.timeOfDay, 'evening');
          expect(seed.dayCount, 3);
          expect(seed.storyStartDate, '1887-06-01');
          expect(seed.storyStartTime, '23:47');
        },
      );

      test('falls back to the first baseline entry for pre-fix groups '
          '(where the wizard stored its only copy)', () {
        // A pre-calendar group: no top-level time on defaultMember, per-member
        // baseline entries carry the wizard's seed.
        const defaultMember = '{"perChar":{"alice":{"affection":10}}}';
        const baseline =
            '{"alice":{"affection":10,"timeOfDay":"night","dayCount":7}}';
        final seed = parseGroupTimeSeed(defaultMember, baseline);
        expect(seed, isNotNull);
        expect(seed!.timeOfDay, 'night');
        expect(seed.dayCount, 7);
        expect(seed.storyStartDate, isNull);
        expect(seed.storyStartTime, isNull);
      });

      test('settings-dialog-style top-level keys win over baseline', () {
        // The group settings dialog writes top-level keys directly.
        const defaultMember =
            '{"perChar":{},"timeOfDay":"afternoon","dayCount":2}';
        const baseline = '{"alice":{"timeOfDay":"night","dayCount":9}}';
        final seed = parseGroupTimeSeed(defaultMember, baseline);
        expect(seed!.timeOfDay, 'afternoon');
        expect(seed.dayCount, 2);
      });

      test('realism-off / blank / garbage blobs yield null', () {
        expect(parseGroupTimeSeed('{}', '{}'), isNull);
        expect(parseGroupTimeSeed('', ''), isNull);
        expect(parseGroupTimeSeed('not json', 'also not json'), isNull);
        expect(parseGroupTimeSeed('{"perChar":{}}', '{}'), isNull);
      });
    },
  );

  group(
    'remapSeedsToMemberIds — source library id → runtime member id (mid)',
    () {
      test('re-keys member entries AND relationship targets to the mid', () {
        final seeds = sampleSeeds(); // keyed by 'alice' / 'bob' (source ids)
        final idMap = {'alice': 'mid-a', 'bob': 'mid-b'};

        final remapped = remapSeedsToMemberIds(seeds, idMap);

        // Member keys are now the mids the realism engine reads.
        expect(remapped.keys, containsAll(['mid-a', 'mid-b']));
        expect(remapped.containsKey('alice'), isFalse);
        // Intragroup relationship targets are re-pointed at the mids too, so
        // "alice feels +40 about bob" survives as "mid-a → {mid-b: 40}".
        expect((remapped['mid-a']!['relationships'] as Map)['mid-b'], 40);
        expect((remapped['mid-b']!['relationships'] as Map)['mid-a'], -20);
        // Scalars/needs ride along untouched.
        expect(remapped['mid-a']!['affection'], 75);
        expect((remapped['mid-a']!['needs'] as Map)['hunger'], 80);
      });

      test('passes through ids (and targets) with no mapping, unchanged', () {
        final remapped = remapSeedsToMemberIds(
          {
            'known': {
              'affection': 10,
              'relationships': {'known': 5, 'stranger': 9},
            },
          },
          {'known': 'mid-k'},
        );
        expect(remapped.keys, ['mid-k']);
        final rels = remapped['mid-k']!['relationships'] as Map;
        expect(rels['mid-k'], 5); // mapped target
        expect(rels['stranger'], 9); // unmapped target left as-is
      });

      test('does NOT mutate the caller\'s seed map', () {
        final seeds = sampleSeeds();
        remapSeedsToMemberIds(seeds, {'alice': 'mid-a', 'bob': 'mid-b'});
        // Original still keyed by the source ids with the original targets.
        expect(seeds.containsKey('alice'), isTrue);
        expect((seeds['alice']!['relationships'] as Map)['bob'], 40);
      });
    },
  );

  // The regression this whole change exists to fix: a creator seed must be
  // reachable at runtime, where the lookup key is the resolved member card's
  // `stableGroupId` (== the group member's UUID / avatar basename `mid`), NOT
  // the source library character's basename the creator seeds under.
  group('end-to-end reachability (real GroupMember id derivation)', () {
    // A library character the user dragged into the group. Its stableGroupId is
    // the image-filename basename — the key the creator historically seeded by.
    final sourceCard = CharacterCard(
      name: 'Alice',
      imagePath: '/library/characters/alice_library.png',
    );
    // The group stores a decoupled copy under a FRESH uuid; the avatar file (and
    // therefore the runtime card's stableGroupId) is that uuid.
    const mid = '11111111-2222-3333-4444-555555555555';
    final memberCard =
        GroupMember(
          id: mid,
          groupId: 'group_1',
          name: 'Alice',
          avatarFilename: '$mid.png',
        ).toCharacterCard(
          resolvedImagePath: '/data/groups/group_1/avatars/$mid.png',
        );

    test('sanity: the id-spaces genuinely differ', () {
      expect(sourceCard.stableGroupId, 'alice_library');
      expect(memberCard.stableGroupId, mid);
      expect(sourceCard.stableGroupId == memberCard.stableGroupId, isFalse);
    });

    test(
      'WITHOUT remap: the seed is NOT reachable by the member id (the bug)',
      () {
        final blobs = buildGroupRealismBlobs(
          seeds: {
            sourceCard.stableGroupId: {'affection': 90, 'trust': 80},
          },
          needsEnabled: true,
          timeOfDay: 'morning',
          dayCount: 1,
        );
        final perChar = parseGroupRealismSeeds(blobs.defaultMemberJson);
        // Runtime reads perChar[memberCard.stableGroupId] → miss → defaults.
        expect(perChar.containsKey(memberCard.stableGroupId), isFalse);
      },
    );

    test('WITH remap: the seed IS reachable by the member id (the fix)', () {
      final remapped = remapSeedsToMemberIds(
        {
          sourceCard.stableGroupId: {'affection': 90, 'trust': 80},
        },
        {sourceCard.stableGroupId: memberCard.stableGroupId},
      );

      final blobs = buildGroupRealismBlobs(
        seeds: remapped,
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );

      // defaultMemberRealismState.perChar is now keyed by the mid the engine reads.
      final perChar = parseGroupRealismSeeds(blobs.defaultMemberJson);
      expect(perChar.containsKey(memberCard.stableGroupId), isTrue);
      expect(perChar[memberCard.stableGroupId]!['affection'], 90);
      // baselineRealismState (read by getBaselineSeedForGroupCharacter via the
      // same mid) is likewise keyed by the mid.
      final baseline = jsonDecode(blobs.baselineJson) as Map<String, dynamic>;
      expect(baseline.containsKey(memberCard.stableGroupId), isTrue);
      expect((baseline[memberCard.stableGroupId] as Map)['trust'], 80);
    });
  });
}
