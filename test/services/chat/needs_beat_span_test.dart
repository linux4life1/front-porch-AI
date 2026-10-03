// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hunger, bladder and bowels follow the span the clock already named. Code does
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
    'an awake span tells hunger, bladder and bowels to move, with no hourly tax',
    () {
      expect(
        needsSpanForBeat(minutes: 150, nextMorning: false, isSkip: false),
        '2 hr 30 min',
      );
      final note = needsBeatNote('2 hr 30 min');
      expect(note, contains('must move with that span'));
      expect(note, contains('A few minutes is a small drop'));
      expect(note, contains('A long stretch is a real one'));
      expect(note, contains('Zero on hunger or bladder or bowels is only legal'));
      expect(note, isNot(contains('per hour')));
      expect(note, isNot(contains('already worn')));
      expect(note, isNot(contains('already applied')));
    },
  );

  test(
    'the same moment, and a cleared beat, allow hunger, bladder and bowels to stay',
    () {
      for (final span in [null, '', 'same moment']) {
        final note = needsBeatNote(span);
        expect(note, contains('stay put'));
        expect(note, isNot(contains('must move with that span')));
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
    final night = needsBeatNote('Next morning');
    expect(night, contains('The night is the whole'));
    expect(night, contains('Sleep still restores energy'));
    expect(night, isNot(contains('must move with that span')));

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
    expect(skip, contains('Do not charge those hours twice'));
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
    expect(needsBeatNote(t.needsSpanLabel), contains('stay put'));
  });

  test(
    'a night skip is Next morning even though the tick chip is empty',
    () async {
      final t = _clock();
      _seed(t);
      await t.detectOocTimeSkip('We sleep through the night.');
      expect(t.bodyTimeLabel, isNull);
      expect(t.needsSpanLabel, 'Next morning');
      expect(t.awakeWearMinutes, 0);
    },
  );

  test(
    'a measured reply and time away name a duration, not a code tax',
    () async {
      final t = _clock();
      await _apply(t, '{"minutes_elapsed": 150, "new_day": false}');
      expect(t.awakeWearMinutes, 0);
      expect(t.bodyTimeLabel, '2 hr 30 min');
      expect(t.needsSpanLabel, '2 hr 30 min');
      expect(
        needsBeatNote(t.needsSpanLabel),
        contains('must move with that span'),
      );

      final away = _clock();
      away.advanceTimePeriods(1);
      expect(away.awakeWearMinutes, 0);
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
    expect(needsBeatNote(t.needsSpanLabel), contains('stay put'));
  });

  test(
    'the needs prompt tells hunger, bladder and bowels to follow the beat',
    () async {
      String? scenePrompt;
      String? awayPrompt;
      final scene = createTestLlmEvalEngine(
        activeChar: CharacterCard(name: 'Nia'),
        streamFactory: (params) {
          scenePrompt = params.prompt;
          return Stream.value(
            '{"hunger_delta":-8,"energy_delta":0,"hygiene_delta":0,'
            '"fun_delta":0,"social_delta":0,"bladder_delta":-6,'
            '"bowels_delta":-4,"comfort_delta":0,"reason":"a long afternoon"}',
          );
        },
      );
      await scene.evaluateNeedsImpactCall('they talked on the porch');
      expect(scenePrompt, contains('HUNGER, BLADDER AND BOWELS FOLLOW THE BEAT'));
      expect(scenePrompt, contains('You choose the size'));
      expect(
        scenePrompt,
        contains('On the same moment, all eight 0 is a quiet beat'),
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
            '"bowels_delta":-8,"comfort_delta":0,"reason":"gone for the afternoon"}',
          );
        },
      );
      await away.evaluateNeedsImpactCall(
        'she came back from the walk',
        awayScene: true,
      );
      expect(awayPrompt, contains('Hunger, bladder and bowels follow that span'));
      expect(
        awayPrompt,
        isNot(contains('Do not also subtract the hours that passed')),
      );
      expect(awayPrompt, isNot(contains('already worn')));
    },
  );

  test('post-gen asks for that span instead of pre-applied wear', () {
    final src = File(
      'lib/services/chat/chat_service_speaker_objectives.dart',
    ).readAsStringSync();
    expect(src, contains('needsBeatNote('));
    expect(src, contains('_timeService.needsSpanLabel'));
    expect(src, isNot(contains('already applied')));
    expect(src, isNot(contains('Report only what the scene did')));
  });

  test('a long hunger drop without food survives the verifier', () async {
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
    expect(drop.status, 'accepted');
    expect(drop.correctedRaw, contains('"hunger_delta": -20'));

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
