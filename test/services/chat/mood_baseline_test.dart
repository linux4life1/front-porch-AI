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

// Standing Mood — a mood the user did not cause.
//
// The maintainer approved this on two conditions, and most of this file exists
// to pin them, because both are the kind of thing that erodes quietly:
//
//   1. It must never reach the evals. A mood that moved bond or trust would
//      turn one bad night into permanent relationship damage the user did not
//      cause and cannot undo.
//   2. It must never be unexplained. An offset with no stated cause is
//      illegible to the user (they read it as randomness) and is an open
//      invitation for a local model to invent a reason and defend it for
//      forty turns.
//
// Condition 2 is why every test below checks the CAUSES alongside the number:
// an offset that arrives without its explanation is a bug even when the
// arithmetic is right.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/mood_baseline.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const good = {
    'energy': 80,
    'hunger': 80,
    'comfort': 80,
    'social': 80,
    'hygiene': 80,
    'fun': 80,
  };

  Map<String, int> needs(Map<String, int> overrides) => {...good, ...overrides};

  group('an unremarkable day says nothing at all', () {
    test('a rested, fed character on a mild afternoon is neutral', () {
      final m = deriveMoodBaseline(needs: good, timeOfDay: 'afternoon');

      expect(m.isNeutral, isTrue);
      expect(m.summary, isEmpty);
      expect(
        m.injection,
        isEmpty,
        reason: 'neutral must cost zero prompt tokens — most turns are this '
            'one, and a fragment saying "nothing in particular" would be paid '
            'for on every single one of them',
      );
    });

    test('no needs at all (simulation off) is not a bad day', () {
      // Needs off must read as "nothing to say", never as every need at zero.
      final m = deriveMoodBaseline(timeOfDay: 'afternoon');

      expect(
        m.isNeutral,
        isTrue,
        reason: 'an absent vector means the feature is off, not that they are '
            'starving, exhausted and filthy',
      );
    });

    test('but the clock and weather still speak when needs are off', () {
      final m = deriveMoodBaseline(timeOfDay: 'night');

      expect(m.isNeutral, isFalse);
      expect(m.causes, ['it is the middle of the night']);
    });
  });

  group('every offset arrives with its reason', () {
    test('exhaustion is named, not just counted', () {
      final m = deriveMoodBaseline(
        needs: needs({'energy': 10}),
        timeOfDay: 'afternoon',
      );

      expect(m.offset, -2);
      expect(m.causes, contains('they are exhausted'));
      expect(
        m.summary,
        'not at their best — they are exhausted',
        reason: 'this exact string is what the mood chip shows on hover; if it '
            'is empty the chip is back to explaining nothing',
      );
    });

    test('causes accumulate and the summary names all of them', () {
      final m = deriveMoodBaseline(
        needs: needs({'energy': 10, 'hunger': 10}),
        timeOfDay: 'afternoon',
      );

      expect(m.offset, -3);
      expect(m.summary, contains('they are exhausted'));
      expect(m.summary, contains('they have not eaten'));
    });

    test('a good day is possible, not just a penalty', () {
      final m = deriveMoodBaseline(
        needs: needs({'energy': 95, 'fun': 80}),
        timeOfDay: 'afternoon',
        weather: const DailyWeather(
          condition: WeatherCondition.clear,
          temp: TempBand.mild,
          season: 'spring',
        ),
      );

      expect(
        m.offset,
        greaterThan(0),
        reason: 'without an upside every character would average slightly '
            'miserable, which is the opposite of the point',
      );
      expect(m.causes, contains('they slept well'));
      expect(m.causes, contains('it is a beautiful day'));
    });

    test('rough weather is a cause, clear weather is a different one', () {
      final storm = deriveMoodBaseline(
        needs: good,
        timeOfDay: 'afternoon',
        weather: const DailyWeather(
          condition: WeatherCondition.storm,
          temp: TempBand.cold,
          season: 'winter',
        ),
      );

      expect(storm.offset, -1);
      expect(storm.causes, ['the weather has been miserable']);
    });

    test('weather absent (feature off) contributes nothing', () {
      final m = deriveMoodBaseline(needs: good, timeOfDay: 'afternoon');
      expect(m.causes, isEmpty);
    });
  });

  group('it tints — it can never drive', () {
    test('the offset is clamped even when everything is wrong at once', () {
      final m = deriveMoodBaseline(
        needs: {
          'energy': 0,
          'hunger': 0,
          'comfort': 0,
          'social': 0,
          'hygiene': 0,
        },
        timeOfDay: 'night',
        weather: const DailyWeather(
          condition: WeatherCondition.storm,
          temp: TempBand.cold,
          season: 'winter',
        ),
      );

      expect(
        m.offset,
        -3,
        reason: 'the raw sum is -7; unclamped it would swamp any genuine '
            'reaction to the user and the engine\'s real work would stop '
            'being visible underneath it',
      );
      expect(
        m.causes.length,
        greaterThan(3),
        reason: 'clamping the NUMBER must not silently drop the reasons — the '
            'user still needs to see why',
      );
    });

    test('a merely peckish character has nothing to report', () {
      final m = deriveMoodBaseline(
        needs: needs({'hunger': 40}),
        timeOfDay: 'afternoon',
      );

      expect(
        m.isNeutral,
        isTrue,
        reason: 'only genuinely low needs speak up, or every turn would carry '
            'a mood line and the signal would mean nothing',
      );
    });
  });

  group('what the model is handed is a fact, never a mood', () {
    test('the fragment states the cause and forbids inventing one', () {
      final m = deriveMoodBaseline(
        needs: needs({'energy': 10}),
        timeOfDay: 'afternoon',
      );

      expect(m.injection, contains('they are exhausted'));
      expect(
        m.injection,
        contains('do NOT raise it as a topic or invent an incident'),
        reason: 'this guardrail is the whole reason the feature is safe on a '
            'local model — without it a small model turns "tired" into a '
            'grievance and the Journal records the grievance as fact',
      );
      expect(
        m.injection.toLowerCase(),
        isNot(contains('bad mood')),
        reason: '"in a bad mood" is an invitation to supply a cause; a state '
            'like "exhausted" has nowhere to go',
      );
    });
  });

  group('it never reaches the evals — the maintainer\'s condition', () {
    // Structural, and honestly labelled: proving this behaviourally needs a
    // live ChatService firing real evals. Read it as "nobody wired it in",
    // not "it cannot get in".
    //
    // It is here because this is the condition the feature shipped on, and the
    // failure would be invisible: a mood quietly feeding the relationship
    // judge would turn one bad night into permanent bond and trust damage the
    // user did not cause, arriving as a plausible-looking chip.
    test('no eval prompt builder or eval leaf mentions the mood', () {
      const evalSources = [
        'lib/services/chat/realism_prompt_builder.dart',
        'lib/services/chat/realism_evals.dart',
        'lib/services/chat/realism_evals.calls.dart',
        'lib/services/chat/realism_evals.one_shot.dart',
        'lib/services/chat/realism_evals.support.dart',
        'lib/services/chat/needs_impact_evaluator.dart',
      ];
      for (final path in evalSources) {
        final src = File(path).readAsStringSync();
        expect(
          src.toLowerCase(),
          isNot(contains('standingmood')),
          reason: '\$path references Standing Mood. Colouring generation is '
              'the whole feature; scoring with it was explicitly ruled out.',
        );
        expect(src, isNot(contains('MoodBaseline')), reason: path);
      }
    });

    test('it is wired to generation and display only', () {
      // The four legitimate consumers. A fifth appearing is the thing to look
      // at, not a reason to widen this list reflexively.
      final wiring = File(
        'lib/services/chat/chat_service_mood.dart',
      ).readAsStringSync();
      expect(wiring, contains('buildStandingMoodInjection'));
      expect(wiring, contains('stampStandingMood'));
      expect(
        wiring,
        isNot(contains('applyDeltas')),
        reason: 'mood must never move bond or trust',
      );
    });
  });

  group('the record round-trips for the chip', () {
    test('toJson/fromJson preserves the number and the reasons', () {
      final m = deriveMoodBaseline(
        needs: needs({'energy': 10, 'hunger': 10}),
        timeOfDay: 'night',
      );
      final back = MoodBaseline.fromJson(m.toJson())!;

      expect(back.offset, m.offset);
      expect(back.causes, m.causes);
      expect(
        back.summary,
        m.summary,
        reason: 'the chip reads this off message metadata turns later; if the '
            'round-trip drops the causes the tooltip goes blank',
      );
    });

    test('junk and absence read back as no mood, not as a crash', () {
      expect(MoodBaseline.fromJson(null), isNull);
      expect(MoodBaseline.fromJson('nonsense'), isNull);
      expect(MoodBaseline.fromJson({'causes': []}), isNull);
      expect(
        MoodBaseline.fromJson({'offset': -9, 'causes': ['x']})!.offset,
        -3,
        reason: 'an out-of-range value from an older or hand-edited record '
            'must clamp, not escape the tint bound',
      );
    });
  });
}
