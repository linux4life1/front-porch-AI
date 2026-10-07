// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hunger and bladder follow the span the clock already named. Code does
// not subtract a points-per-hour tax. A same-moment beat may stay at 0.
// A long beat's hunger drop must survive the verifier when nobody ate.
// A hunger gain without eat/food is still crushed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show RealismVerification, evalJsonBool, evalJsonInt;
import 'package:front_porch_ai/services/chat/time_service.dart';

import 'llm_eval_engine_test.dart' show createTestLlmEvalEngine;

TimeService _clock({Map<String, dynamic>? pending}) => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (key, value) {
    pending?[key] = value;
  },
  onPatchLastMessageRealismState: (_, _, _) {},
);

void _seed(TimeService t) {
  t.seedFromV2OrExt(
    dayCount: 1,
    timeOfDay: 'evening',
    storyStartDate: '2026-08-22',
    storyStartTime: '20:31',
  );
}

Future<void> _apply(TimeService t, String json) {
  return t.evaluateTimeProgressAndPostureIfNeeded(
    charName: 'Nia',
    recent: 'User: hi\nNia: hello',
    shortTermTierName: 'Warm',
    onChunk: null,
    fireLLMEval: (prompt, {onChunk}) async => json,
    stripThinkBlocks: (s) => s,
    extractJsonBool: (text, key) {
      final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(text);
      return m == null ? null : m.group(1) == 'true';
    },
    setSpatialStance: (_) {},
    getCurrentSpatialStance: () => '',
    getCharacterEmotion: () => '',
    getEmotionIntensity: () => '',
    timeOnly: true,
  );
}

void main() {
  test(
    // Needs v2 (2026-10-06): the clock charges the span in code; the judge
    // is told so and scores events only. Zero is a valid answer.
    'an awake span tells the judge time is already charged, events only',
    () {
      expect(
        needsSpanForBeat(minutes: 150, nextMorning: false, isSkip: false),
        '2 hr 30 min',
      );
      final note = needsBeatNote('2 hr 30 min');
      expect(note, contains('time has already been charged'));
      expect(note, contains('Score only what the scene itself did'));
      expect(note, contains('A quiet reply is all zeros'));
      expect(note, isNot(contains('You choose the size')));
      expect(note, isNot(contains('Zero on hunger or bladder is only legal')));
      expect(note, isNot(contains('already applied')));
    },
  );

  test(
    'the same moment, and a cleared beat, allow hunger and bladder to stay',
    () {
      for (final span in [null, '', 'same moment']) {
        final note = needsBeatNote(span);
        expect(note, contains('Time charged nothing'));
        expect(note, isNot(contains('time has already been charged for it')));
      }
      expect(
        needsSpanForBeat(minutes: 0, nextMorning: false, isSkip: false),
        'same moment',
      );
    },
  );

  test('a night is the whole change, and a skip keeps the destination', () {
    expect(
      needsSpanForBeat(
        minutes: 0,
        nextMorning: true,
        isSkip: true,
        skipDestination: 'Sun, Aug 23 · 8:00 AM',
      ),
      'Next morning',
    );
    // Needs v2: a night is never assumed; the judge is asked if they slept.
    final night = needsBeatNote('Next morning');
    expect(night, contains('Did they sleep?'));
    expect(
      night,
      contains('If they stayed up, leave energy where the time left it'),
    );
    expect(night, isNot(contains('The night is the whole')));

    const dest = 'Sun, Aug 23 · 4:00 PM';
    expect(
      needsSpanForBeat(
        minutes: 0,
        nextMorning: false,
        isSkip: true,
        skipDestination: dest,
      ),
      dest,
    );
    final skip = needsBeatNote(dest);
    expect(skip, contains('skipped to $dest'));
    expect(
      skip,
      contains('If the skip crossed a night, ask whether they slept'),
    );
    expect(
      needsSpanForBeat(minutes: 0, nextMorning: false, isSkip: true),
      isNull,
    );
  });

  test('the clock stores that span and Continue can clear it', () async {
    final pending = <String, dynamic>{};
    final t = _clock(pending: pending);
    _seed(t);

    await t.detectOocTimeSkip('we drive for several hours');
    expect(t.bodyTimeLabel, isNull);
    expect(t.needsSpanLabel, pending['time_skip_to']);
    expect(t.needsSpanLabel, isNotNull);
    final span = t.needsSpanLabel;

    await _apply(t, '{"minutes_elapsed": 5, "new_day": false}');
    expect(
      t.needsSpanLabel,
      span,
      reason: 'the post-reply eval must not replace a skip the clock owns',
    );

    t.clearBodyBeat();
    expect(t.needsSpanLabel, isNull);
    expect(needsBeatNote(t.needsSpanLabel), contains('Time charged nothing'));
  });

  test(
    'a night skip is Next morning even though the tick chip is empty',
    () async {
      final t = _clock();
      _seed(t);
      await t.detectOocTimeSkip('We sleep through the night.');
      expect(t.bodyTimeLabel, isNull);
      expect(t.needsSpanLabel, 'Next morning');
      // Needs v2: the night is a span the body wears, off-screen.
      expect(t.bodyWearMinutes, greaterThan(0));
      expect(t.bodyBeatOffScreen, isTrue);
    },
  );

  test(
    'a measured reply and time away name a duration, not a code tax',
    () async {
      final t = _clock();
      await _apply(t, '{"minutes_elapsed": 150, "new_day": false}');
      // Needs v2: the clock charges the 150 minutes in code; the judge is
      // told so and scores events only.
      expect(t.bodyWearMinutes, 150);
      expect(t.bodyBeatOffScreen, isFalse);
      expect(t.bodyTimeLabel, '2 hr 30 min');
      expect(t.needsSpanLabel, '2 hr 30 min');
      expect(
        needsBeatNote(t.needsSpanLabel),
        contains('time has already been charged'),
      );

      final away = _clock();
      away.advanceTimePeriods(1);
      expect(away.bodyWearMinutes, greaterThan(0));
      expect(away.bodyBeatOffScreen, isTrue);
      expect(away.needsSpanLabel, away.bodyTimeLabel);
      expect(minutesFromTimePassed(away.needsSpanLabel), greaterThan(0));

      away.resetForFreshChat();
      expect(away.needsSpanLabel, isNull);
    },
  );

  test('a same-moment reply stores no span to charge', () async {
    final t = _clock();
    await _apply(
      t,
      '{"minutes_elapsed": 0, "continuous_instant": true, "new_day": false}',
    );
    expect(t.needsSpanLabel, 'same moment');
    expect(needsBeatNote(t.needsSpanLabel), contains('Time charged nothing'));
  });

  test('the needs prompt tells the judge time is already charged', () async {
    String? scenePrompt;
    String? awayPrompt;
    final scene = createTestLlmEvalEngine(
      activeChar: CharacterCard(name: 'Nia'),
      streamFactory: (params) {
        scenePrompt = params.prompt;
        return Stream.value(
          '{"hunger_delta":-8,"energy_delta":0,"hygiene_delta":0,'
          '"fun_delta":0,"social_delta":0,"bladder_delta":-6,'
          '"comfort_delta":0,"reason":"a long afternoon"}',
        );
      },
    );
    await scene.evaluateNeedsImpactCall('they talked on the porch');
    // Needs v2: the span is charged in code, the judge scores events.
    expect(scenePrompt, contains('TIME HAS ALREADY BEEN CHARGED'));
    expect(scenePrompt, isNot(contains('HUNGER AND BLADDER FOLLOW THE BEAT')));
    expect(scenePrompt, contains('Do not charge the span again'));
    expect(
      scenePrompt,
      contains('All seven 0 is a quiet beat, and a valid answer'),
    );
    expect(scenePrompt, isNot(contains('already worn off the bars')));
    expect(scenePrompt, isNot(contains('TIME WEAR IS HANDLED SEPARATELY')));
    expect(scenePrompt, isNot(contains('per hour')));

    final away = createTestLlmEvalEngine(
      activeChar: CharacterCard(name: 'Nia'),
      streamFactory: (params) {
        awayPrompt = params.prompt;
        return Stream.value(
          '{"hunger_delta":-12,"energy_delta":0,"hygiene_delta":0,'
          '"fun_delta":0,"social_delta":0,"bladder_delta":-10,'
          '"comfort_delta":0,"reason":"gone for the afternoon"}',
        );
      },
    );
    await away.evaluateNeedsImpactCall(
      'she came back from the walk',
      awayScene: true,
    );
    expect(awayPrompt, contains('Time has already been charged for the beat'));
    expect(
      awayPrompt,
      isNot(contains('Do not also subtract the hours that passed')),
    );
    expect(awayPrompt, isNot(contains('already worn')));
  });

  test('post-gen asks for that span instead of pre-applied wear', () {
    final src = File(
      'lib/services/chat/chat_service_speaker_objectives.dart',
    ).readAsStringSync();
    expect(src, contains('needsBeatNote('));
    expect(src, contains('_timeService.needsSpanLabel'));
    expect(src, isNot(contains('already applied')));
    expect(src, isNot(contains('Report only what the scene did')));
  });

  // Needs v2: the clock charges the span, so a judge drop with no cost in
  // the scene is a second charge and is corrected like a gain.
  test('a long hunger drop without food is corrected like a gain', () async {
    final verifier = RealismVerification(
      fireLLMEval: (p, {onChunk}) async => null,
      stripThinkBlocks: (s) => s,
      extractJsonInt: evalJsonInt,
      extractJsonBool: evalJsonBool,
      getActiveCharacter: () => null,
      getActiveGroup: () => null,
      getIsObserverMode: () => false,
      getUserName: () => 'You',
      getMessages: () => const [],
      getRealismVerificationEnabled: () => true,
      getVerificationMaxReprocesses: () => 1,
      getVerificationStrictness: () => 3,
    );
    final drop = await verifier.verify(
      evalKind: 'needs_impact',
      rawOutput: '{"hunger_delta": -20, "reason": "a long afternoon"}',
      sceneResponse: 'we sat on the porch and swapped stories',
    );
    expect(drop.status, 'corrected');
    expect(drop.correctedRaw, contains('"hunger_delta": -2'));

    final gain = await verifier.verify(
      evalKind: 'needs_impact',
      rawOutput: '{"hunger_delta": 20, "reason": "just chatting"}',
      sceneResponse: 'we sat on the porch and swapped stories',
    );
    expect(gain.status, 'corrected');
    expect(gain.correctedRaw, contains('"hunger_delta": 2'));
    expect(gain.correctedRaw, isNot(contains('20')));
  });
}
