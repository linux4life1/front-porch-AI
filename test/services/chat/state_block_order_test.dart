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

// The order of the `[How <name> is right now: …]` block, read end to end.
//
// THE GAP THIS FILLS. Every fragment in that block had a test. Nothing tested
// the BLOCK. Each was appended wherever it happened to be written, over months,
// and the result was never read as one piece — so it told a character she was
// starving four lines before telling her what was in her pocket, staged her
// physical position dead last after everything she might do from it, said "she
// came in not at their best" before any of the weather or needs that explain why,
// and split how-she-feels-about-people across the very top and the very bottom.
//
// Every one of those is invisible to a per-fragment test, because every
// fragment was individually correct.
//
// A model reads this top to bottom and each line is conditioned by what came
// before, so the contract is: a fact that explains another fact comes first,
// and a directive comes after everything it refers to. This builds ONE block
// with 15 of the 17 fragments genuinely populated and asserts the whole
// sequence.
//
// The two not populated here need a live group (inter-character feelings) or a
// database (open commitments). Both are ordered in source between fragments
// that ARE asserted below, so a reshuffle still trips this test — but they are
// named in `notPopulated` so the gap is written down rather than implied.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

void main() {
  /// Fragments this harness cannot reach, recorded rather than glossed over.
  /// Inter-character feelings needs a live group; open commitments needs a
  /// database. Both are ordered in source beside fragments that ARE asserted
  /// here, so a reshuffle of the block still trips the sequence below.
  const notPopulated = ['inter-character feelings', 'open commitments'];

  /// Every fragment that can be populated without a database or a live group,
  /// switched on at once — which no other test in the suite does.
  String fullBlock() {
    final card = CharacterCard(
      name: 'Alice',
      frontPorchExtensions: FrontPorchExtensions(
        ambitions: ['open her own bakery'],
        likes: ['thunderstorms'],
        dislikes: ['being interrupted'],
      ),
    );

    final rel = RelationshipService(
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

    final nsfw = NsfwService(
      getGroupInt: (id, key, {defaultValue = 0}) => defaultValue,
      getGroupValue: (id, key) => null,
      setGroupValue: (id, key, v) {},
    )..loadNsfwScalars(
      nsfwCooldownEnabled: true,
      arousalLevel: 0,
      cooldownTurnsRemaining: 2,
      cooldownTurnsTotal: 4,
    );

    final sim = NeedsSimulation(
      onNotify: () {},
      onSaveChat: () async {},
      getTimeOfDay: () => 'evening',
      getRealismEnabled: () => true,
      getObserverMode: () => true,
      getCurrentSpeakerIdForRealism: () => '',
      getIsGroupNonObserverMode: () => false,
      getGroupNeeds: (_) => const {},
      setGroupNeeds: (_, _) {},
      getEnjoysLowHygiene: () => false,
      getNeedsSimEnabled: () => true,
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
        getRealismEnabled: () => true,
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
        getRealismEnabled: () => true,
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
        getPockets: (_) => Pockets(carrying: [const PocketItem('candy bar')]),
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
        getRealismEnabled: () => true,
      ),
      nsfwInjection: NsfwInjection(
        nsfwService: nsfw,
        getRealismEnabled: () => true,
        getActiveCharacter: () => card,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
      ),
      needsInjection: NeedsInjection(
        needsSimulation: sim,
        getNeedsSimEnabled: () => true,
        getRealismEnabled: () => true,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getEnjoysLowHygiene: () => false,
        getGroupNeeds: (_) => const {},
        getCharacterIdFromCard: (c) => c.name,
      ),
      getRealismEnabled: () => true,
      getClockRunningOverride: () => true,
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

  /// A distinctive substring of each fragment, in the order they must appear.
  /// Deliberately the text a reader would recognise, so a failure names the
  /// fragment rather than an index.
  const expectedOrder = <String, String>{
    'time': 'day 1 of the story',
    'absence note': 'Out of story:',
    'weather': 'rain',
    'position': 'Position: leaning against the counter',
    // NOT the character's bare name: that matches the block header three
    // characters in, which silently made this assertion about nothing.
    'bond': 'deepening, stable connection',
    'trust behaviour': 'genuinely trusts',
    'ambitions': 'open her own bakery',
    'tastes': 'Tastes: drawn to thunderstorms',
    'standing mood': 'Before this conversation started',
    'emotion': 'Mood: Wistful',
    'fixation': 'On the mind lately',
    'inventory': 'candy bar',
    'needs': 'Hunger:',
    'body': 'Body:',
    'join': 'reach for it before looking elsewhere',
  };

  test('the whole block reads in a sensible order', () {
    final block = fullBlock();

    // Every fragment must actually be present, or an ordering assertion below
    // would pass vacuously on a block that simply lost one.
    for (final e in expectedOrder.entries) {
      expect(
        block,
        contains(e.value),
        reason: '${e.key} is missing — the ordering checks below would be '
            'meaningless without it',
      );
    }

    final positions = [
      for (final e in expectedOrder.entries) (e.key, block.indexOf(e.value)),
    ];
    for (var i = 1; i < positions.length; i++) {
      expect(
        positions[i].$2,
        greaterThan(positions[i - 1].$2),
        reason: '"${positions[i].$1}" must come after "${positions[i - 1].$1}"'
            ' — see the section comments in realism_state_injection.dart for '
            'why this sequence and not another',
      );
    }
  });

  group('the specific inversions this order was written to fix', () {
    late String block;
    setUp(() => block = fullBlock());

    int at(String s) => block.indexOf(s);

    test('she knows what she carries before she is told she needs it', () {
      expect(at('candy bar'), lessThan(at('Hunger:')));
    });

    test('staging comes before the state she would act from', () {
      // "Position: … — ground actions in this" used to be the LAST line in the
      // block, after everything she might do from it.
      expect(at('Position:'), lessThan(at('Mood: Wistful')));
      expect(at('Position:'), lessThan(at('Hunger:')));
    });

    test('the weather that explains her mood precedes the mood', () {
      // Standing mood is DERIVED from weather and needs. It used to be stated
      // two lines above the weather and eight above the needs — the conclusion
      // before any of its evidence.
      expect(at('rain'), lessThan(at('Before this conversation started')));
    });

    test('the baseline mood precedes the current one it sits under', () {
      expect(
        at('Before this conversation started'),
        lessThan(at('Mood: Wistful')),
      );
    });

    test('the background thought sits with the mood it says it colours', () {
      // "a background thought that colors mood and reactions", formerly nine
      // fragments below the mood in question.
      expect(at('On the mind lately'), greaterThan(at('Mood: Wistful')));
      expect(
        at('On the mind lately'),
        lessThan(at('Hunger:')),
        reason: 'it belongs in the mental-state run, not adrift below needs',
      );
    });

    test('the join is the last thing before the closing instruction', () {
      expect(
        at('reach for it before looking elsewhere'),
        greaterThan(at('Body:')),
        reason: 'it reads backwards over what she has, needs and feels, so it '
            'has to follow all of them',
      );
      expect(
        at('reach for it before looking elsewhere'),
        lessThan(at('Express all of this')),
      );
    });
  });

  test('the gaps in this harness are written down, not implied', () {
    // Guards the comment at the top: if someone populates these later they
    // should add them to expectedOrder rather than leaving a stale note.
    expect(notPopulated, hasLength(2));
  });
}
