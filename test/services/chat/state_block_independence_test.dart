// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// THE STATE BLOCK IS NOT A REALISM FEATURE — it is the delivery vehicle for
// eleven fragments, only some of which are.
//
// Found by an audit on 2026-08-08, and it is the biggest instance yet of the
// class this project keeps hitting: correct code that a guard means nobody ever
// reaches. `chat_service_generation_plan.dart` wrapped the whole block in
// `if (_realismActiveThisMode)`. The composer had ALREADY been taught to gate
// each fragment individually — its own comment says a blanket early return
// "silently deleted all eleven fragments, including the four that are not
// realism features" — but that blanket gate had simply MOVED to the caller,
// where the per-fragment gating never got to run.
//
// So with the Realism Engine off, all of this was built and discarded:
//   * Pockets & Wardrobe   — Porch Life says "works alone"
//   * Likes & Dislikes     — its fragment is commented "DELIBERATELY NOT
//                            REALISM-GATED", inside the gate
//   * Ambitions            — chipped "needs Objectives"
//   * Promises             — chipped "needs the Journal"
//   * the absence note     — LIFTED out of TimeInjection specifically to escape
//                            a gate, and landed inside another one
//   * time + weather       — so the standalone story clock, which exists to run
//                            with the engine off, spent an LLM call every turn
//                            to advance a clock whose reading could not reach
//                            the model
//
// These tests drive the REAL composer with the real gate wiring, because the
// bug was never in a fragment — every fragment's own unit tests were green
// throughout. It was in whether the composer ran at all.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

void main() {
  String block({required bool engineOn, bool clockRunning = true}) {
    final card = CharacterCard(
      name: 'Alice',
      frontPorchExtensions: FrontPorchExtensions(
        ambitions: ['open her own bakery'],
        likes: ['thunderstorms'],
        dislikes: ['being interrupted'],
        inventory: {
          'worn': ['flour-dusted apron'],
          'carrying': ['shop keys'],
        },
      ),
    );

    final rel =
        RelationshipService(
          onNotify: () {},
          onSaveChat: () async {},
          getIsGroupActive: () => false,
          getObserverMode: () => true,
          getGroupCharacterCount: () => 0,
          getShouldTrackInterCharacterRelationships: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getCurrentGroupMemberIds: () => const {},
          getOtherGroupMemberIds: (_) => const [],
          getOtherGroupMemberIdToLowerName: (_) => const {},
          getRecentExchangeLowerText: () => '',
          getMessageCount: () => 0,
          getIsGroupRealismActive: () => false,
          getGroupAffectionScore: (id, {defaultValue = 0}) => defaultValue,
          getGroupRelationshipTier: (id, {defaultValue = 0}) => defaultValue,
          setGroupRelationshipTier: (id, v) {},
          getGroupLongTermTier: (id, {defaultValue = 0}) => defaultValue,
          setGroupLongTermTier: (id, v) {},
          getGroupSpatialStance: (id, {defaultValue = ''}) => defaultValue,
          setGroupSpatialStance: (id, v) {},
          getGroupInterCharacterRelationships: (id) => const {},
          setGroupInterCharacterRelationships: (id, m) {},
          setGroupAffectionScore: (id, v) {},
          getGroupLongTermScore: (id, {defaultValue = 0}) => defaultValue,
          setGroupLongTermScore: (id, v) {},
          getGroupTrustLevel: (id, {defaultValue = 0}) => defaultValue,
          setGroupTrustLevel: (id, v) {},
          getGroupFixation: (id, {defaultValue = ''}) => defaultValue,
          setGroupFixation: (id, v) {},
          getGroupFixationLifespan: (id, {defaultValue = 0}) => defaultValue,
          setGroupFixationLifespan: (id, v) {},
        )..loadScalars(
          affectionScore: 60,
          longTermScore: 60,
          trustLevel: 60,
          activeFixation: 'the letter she never sent',
          fixationLifespan: 5,
          spatialStance: 'leaning against the counter',
        );

    final nsfw =
        NsfwService(
          getGroupInt: (id, key, {defaultValue = 0}) => defaultValue,
          getGroupValue: (id, key) => null,
          setGroupValue: (id, key, v) {},
        )..loadNsfwScalars(
          nsfwCooldownEnabled: true,
          arousalLevel: 0,
          // 2026-10-06: the refractory counts story minutes now; 2 of 4 turns
          // with the opening turn spoken is 30 of 60 min, the same body line.
          refractory: const Refractory(minutes: 30, total: 60, opened: true),
        );

    final sim =
        NeedsSimulation(
          onNotify: () {},
          onSaveChat: () async {},
          getTimeOfDay: () => 'evening',
          getRealismEnabled: () => engineOn,
          getObserverMode: () => true,
          getCurrentSpeakerIdForRealism: () => '',
          getIsGroupNonObserverMode: () => false,
          getGroupNeeds: (_) => const {},
          setGroupNeeds: (_, _) {},
          getEnjoysLowHygiene: () => false,
          getNeedsSimEnabled: () => engineOn,
        )..restoreFromSnapshot({
          'vector': {'hunger': 5},
        });

    const day = DailyWeather(
      condition: WeatherCondition.rain,
      temp: TempBand.cool,
      season: 'spring',
    );

    return RealismStateInjection(
      relationshipInjection: RelationshipInjection(
        relationshipService: rel,
        getRealismEnabled: () => engineOn,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getActiveCharacter: () => card,
        getShouldTrackInterCharacterRelationships: () => false,
        getGroupInt: (id, key, {defaultValue = 0}) => defaultValue,
        getCharacterIdFromCard: (c) => c.name,
        getInterCharacterRelationships: (_) => const {},
      ),
      emotionInjection: EmotionInjection(
        getRealismEnabled: () => engineOn,
        getCharacterEmotion: () => 'wistful',
        getEmotionIntensity: () => 'moderate',
      ),
      timeInjection: TimeInjection(
        timeService: TimeService(
          onNotify: () {},
          onSaveChat: () async {},
          onSetPendingRealismMetadata: (_, _) {},
          onPatchLastMessageRealismState: (_, _, _) {},
        ),
      ),
      weatherInjection: WeatherInjection(
        getWeather: () => const SegmentWeather(
          day: day,
          segment: DaySegment.evening,
          condition: WeatherCondition.rain,
          tempC: 9,
        ),
        getPreviousSegment: () => null,
        getUpcoming: () => null,
      ),
      ambitionInjection: AmbitionInjection(
        ambitionService: AmbitionService(
          journalStore: JournalStore(getDb: () => null),
          growthStore: GrowthStore(getDb: () => null),
          fireEval: (_) async => null,
          getMaxCards: () => 30,
        ),
        // A real id: buildAmbitionInjection returns '' without one, and a
        // silently absent fragment would make the ordering checks vacuous.
        getSessionId: () => 's-order',
        getActiveCharacter: () => card,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
      ),
      preferencesInjection: PreferencesInjection(
        getActiveCharacter: () => card,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
        getNsfwEnabled: () => false,
      ),
      inventoryInjection: InventoryInjection(
        getActiveCharacter: () => card,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
        getCurrentDay: () => 0,
        getPockets: (_) => Pockets(
          worn: [const PocketItem('flour-dusted apron')],
          carrying: [const PocketItem('shop keys')],
        ),
      ),
      promiseDebtInjection: PromiseDebtInjection(
        promiseDebtService: PromiseDebtService(
          journalStore: JournalStore(getDb: () => null),
          fireEval: (_) async => null,
          getMaxCards: () => 30,
          applyTrustDelta: (_) {},
          applyBondDelta: (_) {},
        ),
        getSessionId: () => null,
        getActiveCharacter: () => card,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
        getUserName: () => 'You',
      ),
      behavioralInjection: BehavioralInjection(
        relationshipService: rel,
        getRealismEnabled: () => engineOn,
      ),
      nsfwInjection: NsfwInjection(
        nsfwService: nsfw,
        getRealismEnabled: () => engineOn,
        getActiveCharacter: () => card,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
      ),
      needsInjection: NeedsInjection(
        needsSimulation: sim,
        getNeedsSimEnabled: () => engineOn,
        getRealismEnabled: () => engineOn,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getEnjoysLowHygiene: () => false,
        getGroupNeeds: (_) => const {},
        getCharacterIdFromCard: (c) => c.name,
      ),
      getRealismEnabled: () => engineOn,
      getClockRunningOverride: () => clockRunning,
      getAbsenceNote: () => '(Out of story: about two days has passed.)',
      getStandingMood: () =>
          '[Before this conversation started, they slept badly.]',
      getIsGroupNonObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getGroupCharacters: () => const [],
      getActiveCharacter: () => card,
      getCharacterIdFromCard: (c) => c.name,
    ).buildRealismStateInjection();
  }

  group('with the Realism Engine OFF', () {
    late String txt;
    setUp(() => txt = block(engineOn: false));

    test('Pockets & Wardrobe still reaches the model', () {
      expect(
        txt,
        contains('flour-dusted apron'),
        reason:
            'Porch Life calls this one "works alone", and it bills a model '
            'request every turn — a user paying for it with the engine off was '
            'getting nothing at all in the prompt',
      );
      expect(txt, contains('shop keys'));
    });

    test('Likes & Dislikes still reaches the model', () {
      expect(
        txt,
        contains('thunderstorms'),
        reason:
            'the fragment is literally commented "DELIBERATELY NOT '
            'REALISM-GATED" and was sitting inside the realism gate',
      );
      expect(txt, contains('being interrupted'));
    });

    test('Ambitions still reach the model', () {
      // Chipped "needs Objectives" in Porch Life, never the engine.
      expect(txt, contains('open her own bakery'));
    });

    test('the real-absence note still reaches the model', () {
      // It was LIFTED out of TimeInjection in 2026-08-07 precisely so it would
      // stop inheriting a gate it had nothing to do with. It landed inside a
      // second one, so the lift changed nothing a user could observe.
      expect(txt, contains('Out of story:'));
    });

    test('the standing mood still reaches the model', () {
      expect(txt, contains('Before this conversation started'));
    });

    test('the block is not empty', () {
      expect(
        txt.trim(),
        isNotEmpty,
        reason:
            'the entire block used to be skipped with the engine off, so '
            'every one of these fragments was built and thrown away',
      );
    });
  });

  test('the story clock reaches the model with the engine off', () {
    // The standalone clock is opt-in and costs one LLM call per turn. Its whole
    // purpose is to keep time moving without the engine — but the READING lives
    // in this block, so while the block was engine-gated the feature could
    // advance a clock nobody could ever see. A per-turn bill for nothing.
    expect(
      block(engineOn: false, clockRunning: true),
      contains('day 1 of the story'),
    );
  });

  test('with no clock running, the time line stays out', () {
    // The corollary, and it must not regress: the time fragment answers to
    // whether a clock is RUNNING, never to passage-of-time alone, or an
    // engine-off user gets the same frozen timestamp every single turn.
    expect(
      block(engineOn: false, clockRunning: false),
      isNot(contains('day 1 of the story')),
    );
  });

  group('the engine fragments are unaffected', () {
    test('with the engine off they stay out', () {
      // The half of this fix that could have gone wrong silently. Un-gating the
      // block must NOT start leaking bond, trust, emotion, position or fixation
      // into chats whose sidebar says nothing is being tracked. They answer to
      // _characterStateEnabled, which production feeds from
      // _realismActiveThisMode — also false in group Director mode and during
      // AFK auto-responses, neither of which has ever seen these lines.
      final txt = block(engineOn: false);

      expect(txt, isNot(contains('leaning against the counter')));
      expect(
        txt,
        isNot(contains('Hunger:')),
        reason:
            'Needs genuinely require the engine — un-gating the block must '
            'not start narrating hunger in a chat that is not simulating it',
      );
      expect(txt, isNot(contains('the letter she never sent')));
      expect(txt, isNot(contains('Mood: Wistful')));
    });

    test(
      'with the engine on they come back, alongside the independent ones',
      () {
        final txt = block(engineOn: true);

        expect(txt, contains('leaning against the counter'));
        expect(txt, contains('Mood: Wistful'));
        expect(txt, contains('flour-dusted apron'));
        expect(txt, contains('thunderstorms'));
      },
    );
  });
}
