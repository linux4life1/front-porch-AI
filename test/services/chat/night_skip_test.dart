// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A finished night lands before they write. Going to bed is still a scene.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/skip_language.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/utils/quoted_speech.dart';

TimeService _clock() => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
);

void main() {
  final evening = DateTime.utc(2026, 8, 22, 20, 31);

  group('skip language', () {
    test('sleep through the night is a skip and a night skip', () {
      const t = 'we sleep through the night';
      expect(hasSkipPhrase(t), isTrue);
      expect(isNightSkip(t), isTrue);
      expect(shouldDetectTimeSkip(t), isTrue);
    });

    test("let's go to bed is a scene, not a skip", () {
      const t = "let's go to bed";
      expect(hasSkipPhrase(t), isFalse);
      expect(isNightSkip(t), isFalse);
      expect(shouldDetectTimeSkip(t), isFalse);
    });

    test('getting sleepy is not a skip', () {
      expect(shouldDetectTimeSkip("i'm getting sleepy"), isFalse);
      expect(isNightSkip('going to sleep now'), isFalse);
    });

    test('hours later is a skip but not a night restore', () {
      expect(hasSkipPhrase('a few hours later'), isTrue);
      expect(isNightSkip('a few hours later'), isFalse);
    });

    test('the next morning still restores the body', () {
      expect(isNightSkip('the next morning, sunlight'), isTrue);
    });

    test('quoted sleep-through is not a skip', () {
      final lower = stripQuotedSpeech(
        '"we sleep through the night," she joked',
      ).toLowerCase();
      expect(shouldDetectTimeSkip(lower), isFalse);
    });
  });

  group('clock landing', () {
    test('sleep through the night lands at next morning', () {
      expect(
        StoryClock.resolveSkipTarget(evening, 'we sleep through the night'),
        DateTime.utc(2026, 8, 23, 8, 0),
      );
    });

    test('slept until dawn lands at next morning', () {
      expect(
        StoryClock.resolveSkipTarget(evening, 'we slept until dawn'),
        DateTime.utc(2026, 8, 23, 8, 0),
      );
    });

    test('detectOocTimeSkip moves 8:31pm to 8am', () async {
      final t = _clock();
      t.seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'evening',
        passageOfTimeEnabled: true,
        storyStartDate: '2026-08-22',
        storyStartTime: '20:31',
      );
      expect(t.clock.hour, 20);
      await t.detectOocTimeSkip('We sleep through the night.');
      expect(t.clock, DateTime.utc(2026, 8, 23, 8, 0));
      expect(t.dayCount, 2);
    });

    test("detectOocTimeSkip ignores let's go to bed", () async {
      final t = _clock();
      t.seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'evening',
        passageOfTimeEnabled: true,
        storyStartDate: '2026-08-22',
        storyStartTime: '20:31',
      );
      await t.detectOocTimeSkip("Let's go to bed.");
      expect(t.clock.hour, 20);
    });
  });

  group('body restore', () {
    test('energy floors at 90, comfort bumps, hunger stays', () {
      final next = applyNightSkipToNeeds({
        'energy': 20,
        'comfort': 40,
        'hunger': 30,
        'bladder': 50,
      });
      expect(next['energy'], 90);
      expect(next['comfort'], 55);
      expect(next['hunger'], 30);
      expect(next['bladder'], 50);
    });

    test('already-rested energy is not lowered', () {
      expect(applyNightSkipToNeeds({'energy': 96})['energy'], 96);
    });

    test('after-reply sleep fill is dropped; coffee-sized bump stays', () {
      final sleep = {'energy': 50, 'comfort': 20, 'hunger': 40};
      suppressSleepDoubleApply(sleep);
      expect(sleep['energy'], 0);
      expect(sleep['comfort'], 0);
      expect(sleep['hunger'], 40);

      final coffee = {'energy': 7, 'hunger': 35};
      suppressSleepDoubleApply(coffee);
      expect(coffee['energy'], 7);
      expect(coffee['hunger'], 35);
    });
  });
}
