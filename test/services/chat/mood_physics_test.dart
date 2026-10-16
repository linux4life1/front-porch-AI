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

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/mood_effects.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';

MoodState _furious({int held = 0, String intensity = 'strong'}) => MoodState(
  label: 'furious',
  intensity: intensity,
  cause: 'he lied about the money',
  held: held,
);

MoodJudgeResult _judge(
  String label,
  String intensity, {
  String? cause,
  MoodChange? change,
}) => MoodJudgeResult(
  label: label,
  intensity: intensity,
  cause: cause,
  change: change,
);

void main() {
  group('words and parsing', () {
    test('intensity rank and word round-trip, unknown is 0', () {
      expect(moodIntensityRank('strong'), 3);
      expect(moodIntensityRank('Moderate'), 2);
      expect(moodIntensityRank('mild'), 1);
      expect(moodIntensityRank(''), 0);
      expect(moodIntensityRank('wobbly'), 0);
      expect(moodIntensityWord(3), 'strong');
      expect(moodIntensityWord(1), 'mild');
      expect(moodIntensityWord(0), '');
    });

    test('emotion_change parses held, stoked, moved and the legacy YES/NO', () {
      expect(parseMoodChange('held'), MoodChange.held);
      expect(parseMoodChange('STOKED'), MoodChange.stoked);
      expect(parseMoodChange('moved'), MoodChange.moved);
      expect(parseMoodChange('YES'), MoodChange.held);
      expect(parseMoodChange('no'), MoodChange.moved);
      expect(parseMoodChange(true), MoodChange.held);
      expect(parseMoodChange(''), isNull);
      expect(parseMoodChange(null), isNull);
      expect(parseMoodChange('maybe'), isNull);
    });

    test('cause is one clean line, capped at twelve words, none is empty', () {
      expect(
        cleanMoodCause('"He lied about the money."'),
        'He lied about the money',
      );
      expect(cleanMoodCause('  none '), '');
      expect(cleanMoodCause('N/A'), '');
      expect(cleanMoodCause(null), '');
      expect(cleanMoodCause('one\ntwo   three'), 'one two three');
      final long = List.generate(20, (i) => 'w$i').join(' ');
      expect(cleanMoodCause(long).split(' ').length, 12);
    });

    test('hold word is nothing, still, then for a while now', () {
      expect(moodHoldWord(0), '');
      expect(moodHoldWord(1), '');
      expect(moodHoldWord(2), 'still');
      expect(moodHoldWord(4), 'still');
      expect(moodHoldWord(5), 'for a while now');
    });

    test(
      'tone family follows the canonical label; unknown and neutral are null',
      () {
        expect(moodToneOf('anger'), MoodTone.sour);
        expect(moodToneOf('prickly'), MoodTone.sour);
        expect(moodToneOf('wistful'), MoodTone.low);
        expect(moodToneOf('Affection'), MoodTone.warm);
        expect(moodToneOf('desire'), MoodTone.charged);
        expect(moodToneOf('nervous'), MoodTone.anxious);
        expect(moodToneOf('relief'), MoodTone.lifted);
        expect(moodToneOf('neutral'), isNull);
        expect(moodToneOf('undone'), isNull);
        expect(moodToneOf(''), isNull);
      },
    );
  });

  group('the schedule', () {
    test('eases on the third and sixth held pass, mild is the floor', () {
      expect(easedMoodRank(3, 1), 3);
      expect(easedMoodRank(3, 2), 3);
      expect(easedMoodRank(3, 3), 2);
      expect(easedMoodRank(2, 4), 2);
      expect(easedMoodRank(2, 6), 1);
      expect(easedMoodRank(1, 6), 1);
      expect(easedMoodRank(1, 9), 1);
    });

    test(
      'a feeling the judge keeps eases strong, moderate, mild over passes',
      () {
        var mood = _furious();
        final seen = <String>[];
        for (var i = 0; i < 7; i++) {
          mood = applyMoodJudge(
            stored: mood,
            judged: _judge('furious', 'strong', change: MoodChange.held),
          );
          seen.add(mood.intensity);
        }
        expect(seen, [
          'strong',
          'strong',
          'moderate',
          'moderate',
          'moderate',
          'mild',
          'mild',
        ]);
        expect(mood.held, 7);
        expect(mood.cause, 'he lied about the money');
        expect(mood.label, 'furious');
      },
    );

    test('a judge that eases faster than the schedule is honoured', () {
      final mood = applyMoodJudge(
        stored: _furious(),
        judged: _judge('furious', 'mild', change: MoodChange.held),
      );
      expect(mood.intensity, 'mild');
      expect(mood.held, 1);
    });

    test('stoked restarts the clock and takes the fresh cause', () {
      final mood = applyMoodJudge(
        stored: _furious(held: 4, intensity: 'moderate'),
        judged: _judge(
          'furious',
          'strong',
          cause: 'and now he denies it',
          change: MoodChange.stoked,
        ),
      );
      expect(mood.intensity, 'strong');
      expect(mood.held, 0);
      expect(mood.cause, 'and now he denies it');
      expect(mood.label, 'furious');
    });

    test('moved takes label, intensity and cause and resets the hold', () {
      final mood = applyMoodJudge(
        stored: _furious(held: 3),
        judged: _judge(
          'Relieved',
          'moderate',
          cause: '"she apologised."',
          change: MoodChange.moved,
        ),
      );
      expect(
        mood,
        const MoodState(
          label: 'relieved',
          intensity: 'moderate',
          cause: 'she apologised',
        ),
      );
    });

    test(
      'a missing change answer compares families: same holds, other moves',
      () {
        final held = applyMoodJudge(
          stored: _furious(),
          judged: _judge('prickly', 'strong'),
        );
        expect(held.held, 1);
        expect(held.label, 'furious');
        final moved = applyMoodJudge(
          stored: _furious(),
          judged: _judge('wistful', 'mild', cause: 'the letter'),
        );
        expect(moved.held, 0);
        expect(moved.label, 'wistful');
        expect(moved.cause, 'the letter');
      },
    );

    test('held with a different family is a move in disguise', () {
      final mood = applyMoodJudge(
        stored: _furious(held: 2),
        judged: _judge('joy', 'strong', change: MoodChange.held),
      );
      expect(mood.label, 'joy');
      expect(mood.held, 0);
    });

    test('a neutral mood can only move; a judged neutral clears', () {
      final set = applyMoodJudge(
        stored: MoodState.neutral,
        judged: _judge('curious', 'mild', change: MoodChange.held),
      );
      expect(set.label, 'curious');
      expect(set.held, 0);
      final cleared = applyMoodJudge(
        stored: _furious(),
        judged: _judge('neutral', '', change: MoodChange.moved),
      );
      expect(cleared.isNeutral, isTrue);
      expect(cleared.label, 'neutral');
      expect(cleared.cause, '');
      expect(cleared.held, 0);
      final kept = applyMoodJudge(
        stored: _furious(),
        judged: _judge('wistful', '', change: MoodChange.moved),
      );
      expect(kept.intensity, 'strong', reason: 'no intensity given: keep');
    });

    test('a story day eases one step; past mild the mood clears', () {
      expect(easeMoodForDays(_furious(), 1).intensity, 'moderate');
      expect(easeMoodForDays(_furious(), 2).intensity, 'mild');
      expect(easeMoodForDays(_furious(), 3), MoodState.neutral);
      expect(easeMoodForDays(_furious(), 27), MoodState.neutral);
      expect(easeMoodForDays(_furious(), 0), _furious());
      expect(easeMoodForDays(_furious(), -1), _furious());
      expect(easeMoodForDays(MoodState.neutral, 5), MoodState.neutral);
    });
  });

  group('stamps', () {
    test('round-trips all four keys', () {
      final stamp = _furious(held: 2).toStamp();
      expect(stamp[kMoodStampCause], 'he lied about the money');
      expect(stamp[kMoodStampHeld], 2);
      expect(MoodState.fromStamp(stamp, MoodState.neutral), _furious(held: 2));
    });

    test('a stamp from before cause and hold reads as a fresh feeling', () {
      final legacy = {kMoodStampLabel: 'joy', kMoodStampIntensity: 'strong'};
      final read = MoodState.fromStamp(legacy, _furious(held: 4));
      expect(read.label, 'joy');
      expect(read.cause, '');
      expect(read.held, 0);
    });

    test('a stamp without a mood keeps the fallback', () {
      expect(
        MoodState.fromStamp({'trust': 50}, _furious(held: 4)),
        _furious(held: 4),
      );
      expect(MoodState.fromStamp(null, _furious()), _furious());
    });
  });

  group('the voice', () {
    test('the mood line scales with intensity and names the cause', () {
      expect(
        moodPromptLine(_furious(intensity: 'mild')),
        'Mood: Furious, mild, since he lied about the money — it colours tone '
        'and word choice.',
      );
      expect(
        moodPromptLine(_furious(intensity: 'moderate')),
        'Mood: Furious, moderate, because he lied about the money — it shapes '
        'what they say and do this turn.',
      );
      expect(
        moodPromptLine(_furious(held: 3)),
        'Mood: Furious, strong, because he lied about the money, still — it '
        'leads this reply: they act on it before anything else.',
      );
      expect(
        moodPromptLine(const MoodState(label: 'flustered', intensity: 'mild')),
        'Mood: Flustered, mild — it colours tone and word choice.',
      );
      expect(moodPromptLine(MoodState.neutral), '');
      expect(moodPromptLine(const MoodState(label: 'neutral')), '');
    });

    test('the effects line speaks at moderate and strong, in their own way', () {
      expect(moodEffectsLine(_furious(intensity: 'mild')), '');
      expect(
        moodEffectsLine(_furious(intensity: 'moderate')),
        startsWith('In their own way: less patience'),
      );
      expect(
        moodEffectsLine(_furious()),
        'In their own way: the grievance comes first: they may refuse, argue, '
        'withdraw or leave before anything else.',
      );
      expect(
        moodEffectsLine(const MoodState(label: 'undone', intensity: 'strong')),
        '',
      );
      for (final tone in MoodTone.values) {
        final (moderate, strong) = kMoodEffectsCopy[tone]!;
        expect(moderate, isNotEmpty);
        expect(strong, isNotEmpty);
      }
    });

    test('the display line reads label, intensity, cause and hold', () {
      expect(
        moodDisplayLine(_furious(held: 5)),
        'Furious (strong) · because he lied about the money · for a while now',
      );
      expect(
        moodDisplayLine(const MoodState(label: 'joy', intensity: 'mild')),
        'Joy (mild)',
      );
      expect(moodDisplayLine(MoodState.neutral), 'Neutral');
    });
  });
}
