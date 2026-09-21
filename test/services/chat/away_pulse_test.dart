// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure Away-return planner: quiet cadence, @-only hard address,
// vocative/mid-sentence quiet priority, At-work exclusion, skip-banner.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/away_pulse.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';
import 'package:front_porch_ai/services/chat/with_user_eval.dart';

CharacterCard _card(String name) => CharacterCard(
  name: name,
  description: 'Exists only inside the away-pulse planner test.',
  firstMessage: 'Evening.',
);

void main() {
  final ana = _card('Ana');
  final bea = _card('Bea');
  final roster = [ana, bea];

  PresenceWhere presenceOf(
    CharacterCard card, {
    required PresenceWhere anaWhere,
    required PresenceWhere beaWhere,
  }) {
    return card.name == 'Ana' ? anaWhere : beaWhere;
  }

  test('user send always pulses; cadence is every 3 present turns', () {
    expect(
      AwayPulse.shouldPulse(fromUserSend: true, presentSpeakerTurns: 0),
      isTrue,
    );
    expect(
      AwayPulse.shouldPulse(fromUserSend: false, presentSpeakerTurns: 0),
      isFalse,
    );
    expect(
      AwayPulse.shouldPulse(fromUserSend: false, presentSpeakerTurns: 2),
      isFalse,
    );
    expect(
      AwayPulse.shouldPulse(fromUserSend: false, presentSpeakerTurns: 3),
      isTrue,
    );
    expect(AwayPulse.cadenceDue(6), isTrue);
  });

  test('quiet pulse list is Away only; At work and With you stay out', () {
    final targets = AwayPulse.quietPulseTargets(
      roster: roster,
      userText: 'Anyone there?',
      presenceOf: (c) => presenceOf(
        c,
        anaWhere: PresenceWhere.away,
        beaWhere: PresenceWhere.atWork,
      ),
    );
    expect(targets.map((c) => c.name), ['Ana']);
  });

  test('mid-sentence name raises quiet priority but is not an address', () {
    expect(
      SceneGuestDirector.isMidSentenceMention('Ana', 'I told Ana about dinner'),
      isTrue,
    );
    expect(
      SceneGuestDirector.isVocativeAddress('Ana', 'I told Ana about dinner'),
      isFalse,
    );
    expect(
      SceneGuestDirector.directlyAddressedCard(
        roster,
        'I told Ana about dinner',
      ),
      isNull,
    );
    final targets = AwayPulse.quietPulseTargets(
      roster: [bea, ana],
      userText: 'I told Ana about dinner',
      presenceOf: (_) => PresenceWhere.away,
    );
    expect(targets.map((c) => c.name), ['Ana', 'Bea']);
  });

  test('@ of Away forces return; vocative only raises quiet priority', () {
    expect(
      SceneGuestDirector.directlyAddressedCard(
        roster,
        'Ana, you coming?',
      )?.name,
      'Ana',
      reason: 'director still sees vocative; Away force does not use it',
    );
    expect(
      SceneGuestDirector.atMentionedCard(roster, '@Ana over here')?.name,
      'Ana',
    );
    expect(
      AwayPulse.addressedAwayMember(
        roster: roster,
        userText: 'Ana, you coming?',
        presenceOf: (c) => presenceOf(
          c,
          anaWhere: PresenceWhere.away,
          beaWhere: PresenceWhere.withYou,
        ),
      ),
      isNull,
      reason: 'soft address: vocative must not force a spoken return',
    );
    expect(
      AwayPulse.addressedAwayMember(
        roster: roster,
        userText: '@Ana over here',
        presenceOf: (c) => presenceOf(
          c,
          anaWhere: PresenceWhere.away,
          beaWhere: PresenceWhere.withYou,
        ),
      )?.name,
      'Ana',
    );
    expect(
      AwayPulse.addressedAwayMember(
        roster: roster,
        userText: '@Bea over here',
        presenceOf: (c) => presenceOf(
          c,
          anaWhere: PresenceWhere.away,
          beaWhere: PresenceWhere.atWork,
        ),
      ),
      isNull,
      reason: 'At work is never entered into this path',
    );
    final targets = AwayPulse.quietPulseTargets(
      roster: [bea, ana],
      userText: 'Ana, you coming?',
      presenceOf: (_) => PresenceWhere.away,
    );
    expect(targets.map((c) => c.name), [
      'Ana',
      'Bea',
    ], reason: 'vocative raises quiet priority like a mid-sentence name');
  });

  test('rejoining hint is only for quiet-flip returns, not forced @', () {
    expect(
      AwayPulse.shouldInjectReturnSpeakHint(forcedByAtMention: false),
      isTrue,
    );
    expect(
      AwayPulse.shouldInjectReturnSpeakHint(forcedByAtMention: true),
      isFalse,
    );
  });

  test('skip banner is live: consumed return does not keep suppressing', () {
    expect(
      AwayPulse.shouldWriteSkipBanner(
        speakerSkips: true,
        hasUnconsumedReturn: false,
      ),
      isTrue,
    );
    expect(
      AwayPulse.shouldWriteSkipBanner(
        speakerSkips: true,
        hasUnconsumedReturn: true,
      ),
      isFalse,
    );
    expect(
      AwayPulse.shouldWriteSkipBanner(
        speakerSkips: false,
        hasUnconsumedReturn: false,
      ),
      isFalse,
    );
  });

  test('addressed Away wins return-speak; else oldest flip; cap is one', () {
    expect(
      AwayPulse.pickReturnSpeak(
        addressedAwayId: 'ana',
        flippedTrueOldestFirst: ['bea', 'ana'],
        alreadyUsedThisSend: false,
      ),
      'ana',
    );
    expect(
      AwayPulse.pickReturnSpeak(
        addressedAwayId: null,
        flippedTrueOldestFirst: ['bea', 'ana'],
        alreadyUsedThisSend: false,
      ),
      'bea',
    );
    expect(
      AwayPulse.pickReturnSpeak(
        addressedAwayId: 'ana',
        flippedTrueOldestFirst: ['bea'],
        alreadyUsedThisSend: true,
      ),
      isNull,
    );
    expect(
      AwayPulse.orderOldestAway([
        (id: 'ana', lastSpokeIndex: 4),
        (id: 'bea', lastSpokeIndex: -1),
      ]),
      ['bea', 'ana'],
    );
  });

  test('quiet detect writes only a real bool; fail/empty stays null', () async {
    final ok = WithUserEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            expect(debugLabel, 'with_user_quiet');
            final p = buildPrompt(toolsMode: false);
            expect(p, contains('they have not spoken this turn'));
            expect(
              p.toLowerCase(),
              isNot(contains('the reply that just happened')),
            );
            return '{"with_user": true}';
          },
    );
    expect(
      await ok.detectQuiet(
        charName: 'Ana',
        userName: 'Ben',
        recentExchange: 'Ben: Evening.',
        stance: 'in the next room',
      ),
      isTrue,
    );

    final down = WithUserEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            throw StateError('backend down');
          },
    );
    expect(
      await down.detectQuiet(
        charName: 'Ana',
        userName: 'Ben',
        recentExchange: 'Ben: Evening.',
      ),
      isNull,
    );
    expect(
      await ok.detectQuiet(charName: 'Ana', userName: 'Ben'),
      isNull,
      reason: 'empty scene + empty stance is fail-closed',
    );
  });
}
