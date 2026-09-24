// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The STANDALONE story clock: the Realism Engine is off, the user opted in,
// and the clock advances on an eval of its own (docs/design/
// feature-independence.md — decoupled 2026-08-06, superseding the 2026-08-02
// "cannot be decoupled" ruling).
//
// The thing worth proving here is not "it moves". It is that it moves the SAME
// WAY the engine's fused scene-time eval does: identical clamp, identical
// failure floor, identical new_day corroboration guard, identical OOC-skip
// ownership. `timeOnly` deliberately shares one code path with the engine
// after the call returns, and these tests are what keep that true — a future
// edit that forks the clock math for one driver has to break one of them.
//
// The engine-ON path stays covered by time_service_test.dart, which this file
// does not touch.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

TimeService makeService() => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
);

/// Day 3, Thursday 2026-07-02, 6:30 PM — the same fixed anchor the engine-path
/// suite uses, so numbers can be compared across the two files by eye.
void seedFixed(TimeService t, {bool passage = true}) => t.seedFromV2OrExt(
  dayCount: 3,
  timeOfDay: 'evening',
  passageOfTimeEnabled: passage,
  storyStartDate: '2026-06-30',
);

/// One turn of the clock. [timeOnly] false is the engine's fused call, true is
/// the standalone one; every other argument is identical, which is the point.
Future<void> runTurn(
  TimeService t, {
  required bool timeOnly,
  String? reply,
  String recent = 'User: hi\nNia: hello',
  void Function(String prompt)? capturePrompt,
  void Function(String stance)? onStance,
}) => t.evaluateTimeProgressAndPostureIfNeeded(
  charName: 'Nia',
  recent: recent,
  shortTermTierName: 'Warm',
  onChunk: null,
  fireLLMEval: (p, {onChunk}) async {
    capturePrompt?.call(p);
    return reply;
  },
  stripThinkBlocks: (s) => s,
  extractJsonBool: (text, key) {
    final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(text);
    return m == null ? null : m.group(1) == 'true';
  },
  setSpatialStance: (s) => onStance?.call(s),
  getCurrentSpatialStance: () => 'leaning on the porch rail',
  getCharacterEmotion: () => 'content',
  getEmotionIntensity: () => 'mild',
  timeOnly: timeOnly,
);

void main() {
  group('standalone clock advances exactly like the engine clock', () {
    test('the same verdict moves both drivers to the same moment', () async {
      final engine = makeService();
      final standalone = makeService();
      seedFixed(engine);
      seedFixed(standalone);

      const verdict =
          '{"minutes_elapsed": 45, "new_day": false, '
          '"posture": "sitting on the steps"}';
      await runTurn(engine, timeOnly: false, reply: verdict);
      await runTurn(standalone, timeOnly: true, reply: verdict);

      expect(standalone.clock, engine.clock);
      expect(standalone.clock, DateTime.utc(2026, 7, 2, 19, 15));
      expect(standalone.dayCount, engine.dayCount);
    });

    test('the per-turn clamp is the same ceiling for both', () async {
      final engine = makeService();
      final standalone = makeService();
      seedFixed(engine);
      seedFixed(standalone);

      // Far past maxMinutesPerTurn — both must land on the ceiling, not the ask.
      const verdict = '{"minutes_elapsed": 99999, "new_day": false}';
      await runTurn(engine, timeOnly: false, reply: verdict);
      await runTurn(standalone, timeOnly: true, reply: verdict);

      expect(standalone.clock, engine.clock);
      expect(
        standalone.clock,
        DateTime.utc(
          2026,
          7,
          2,
          18,
          30,
        ).add(Duration(minutes: StoryClock.maxMinutesPerTurn)),
      );
    });

    test('a failed eval drifts by the same deterministic floor', () async {
      final engine = makeService();
      final standalone = makeService();
      seedFixed(engine);
      seedFixed(standalone);

      // null reply = the call came back empty. The drift is a FAILURE cushion,
      // not a time model — but it must cushion both drivers identically.
      await runTurn(engine, timeOnly: false, reply: null);
      await runTurn(standalone, timeOnly: true, reply: null);

      expect(standalone.clock, engine.clock);
      expect(
        standalone.clock,
        DateTime.utc(
          2026,
          7,
          2,
          18,
          30,
        ).add(Duration(minutes: StoryClock.conversationalFloorMinutes)),
      );
    });

    test('new_day needs the same corroboration in both drivers', () async {
      const claimsNewDay = '{"minutes_elapsed": 5, "new_day": true}';

      // Uncorroborated: no sleep/wake language, so the flag is suppressed and
      // only the clamped minutes apply. This guard exists because small models
      // hallucinate new_day; the standalone path must not be the soft way in.
      final engineNo = makeService();
      final standaloneNo = makeService();
      seedFixed(engineNo);
      seedFixed(standaloneNo);
      await runTurn(engineNo, timeOnly: false, reply: claimsNewDay);
      await runTurn(standaloneNo, timeOnly: true, reply: claimsNewDay);
      expect(standaloneNo.clock, engineNo.clock);
      expect(standaloneNo.dayCount, 3, reason: 'no night was actually crossed');

      // Corroborated: the exchange really does cross a night.
      const slept = 'User: goodnight\nNia: she falls asleep beside him';
      final engineYes = makeService();
      final standaloneYes = makeService();
      seedFixed(engineYes);
      seedFixed(standaloneYes);
      await runTurn(
        engineYes,
        timeOnly: false,
        reply: claimsNewDay,
        recent: slept,
      );
      await runTurn(
        standaloneYes,
        timeOnly: true,
        reply: claimsNewDay,
        recent: slept,
      );
      expect(standaloneYes.clock, engineYes.clock);
      expect(standaloneYes.dayCount, 4);
    });

    test(
      'an OOC skip owns the turn, so the eval cannot double-advance',
      () async {
        final t = makeService();
        seedFixed(t);
        t.detectOocTimeSkip('(OOC: skip ahead a few hours)');
        final afterSkip = t.clock;
        expect(afterSkip, DateTime.utc(2026, 7, 2, 20, 30));

        // The standalone eval still runs this turn, and must count nothing —
        // this is the "Time skip: 11:50 PM chip under a 1:05 AM clock" bug.
        await runTurn(
          t,
          timeOnly: true,
          reply: '{"minutes_elapsed": 45, "new_day": false}',
        );
        expect(t.clock, afterSkip);
      },
    );
  });

  group('standalone mode asks for time and nothing else', () {
    test(
      'the prompt drops posture, emotion and relationship tension',
      () async {
        final t = makeService();
        seedFixed(t);
        String? prompt;
        await runTurn(
          t,
          timeOnly: true,
          reply: '{"minutes_elapsed": 10, "new_day": false}',
          capturePrompt: (p) => prompt = p,
        );

        expect(prompt, isNotNull);
        // Realism scalars: nothing reads them with the engine off, so paying
        // tokens to produce them would be spending a user's budget on a value
        // that gets dropped.
        expect(prompt, isNot(contains('posture')));
        expect(prompt, isNot(contains('Relationship tension')));
        expect(prompt, isNot(contains('content'))); // the emotion scalar
        expect(prompt, isNot(contains('leaning on the porch rail')));
        // But it still asks the one question the clock exists to answer, with
        // the same ceiling the engine states.
        expect(prompt, contains('minutes_elapsed'));
        expect(prompt, contains('new_day'));
        expect(prompt, contains('${StoryClock.maxMinutesPerTurn}'));
      },
    );

    // AMENDED 2026-08-08 (maintainer-approved test change). This asserted
    // `contains('posture')` — that the engine's pre-generation clock call also
    // asked the model where the character was standing. That is no longer true,
    // and the old assertion now pins the BUG rather than the behaviour:
    //
    // posture was answered BEFORE the reply that moves her existed, so a
    // position the character established in her own words could not reach a
    // single prompt — the next turn's pre-generation judge overwrote it first.
    // Meanwhile the prompt asserted the stale one imperatively ("Position: X —
    // ground actions in this"). That is the teleporting the feature exists to
    // prevent, produced by the feature itself. Maintainer ruling: "spatial
    // awareness check should run post character message, otherwise how could it
    // check where she moved". Posture now has its own post-generation pass.
    //
    // The replacement is deliberately stronger than a deletion: it pins the new
    // split so a relapse is caught. The engine call keeps the realism context
    // the standalone clock drops (that contrast is what this group is for), and
    // must NOT ask for posture — asking would pay for a field that is discarded,
    // and the next turn's answer would overwrite the post-generation one, which
    // is exactly how the bug worked.
    test('the engine prompt keeps its realism context but no longer asks '
        'for posture', () async {
      final t = makeService();
      seedFixed(t);
      String? prompt;
      await runTurn(
        t,
        timeOnly: false,
        reply: '{"minutes_elapsed": 10, "new_day": false}',
        capturePrompt: (p) => prompt = p,
      );

      // The contrast this group exists to draw: the engine call still carries
      // the realism context the standalone clock strips.
      expect(prompt, contains('Relationship tension'));
      expect(prompt, contains('minutes_elapsed'));
      // Posture belongs to the post-generation pass now, on BOTH paths.
      expect(prompt, isNot(contains('posture')));
    });

    test('posture is never written while the engine is off', () async {
      final t = makeService();
      seedFixed(t);
      final stances = <String>[];
      // A model that answers with posture anyway (the schema does not forbid
      // extra keys) must still not have it stored — spatialStance is realism
      // state, and a frozen engine must stay frozen.
      await runTurn(
        t,
        timeOnly: true,
        reply: '{"minutes_elapsed": 10, "new_day": false, "posture": "pacing"}',
        onStance: stances.add,
      );
      expect(stances, isEmpty);
    });

    test(
      'passage of time off means no call at all, not a silent one',
      () async {
        final t = makeService();
        seedFixed(t, passage: false);
        final before = t.clock;
        var called = false;
        await runTurn(
          t,
          timeOnly: true,
          reply: '{"minutes_elapsed": 45}',
          capturePrompt: (_) => called = true,
        );
        expect(
          called,
          isFalse,
          reason: 'standalone must not bill a frozen clock',
        );
        expect(t.clock, before);
      },
    );
  });

  group('the time-only tool schema', () {
    test('keeps the tool name so the parse path stays shared', () {
      final fused = kSceneTimeEvalTools.single['function'] as Map;
      final only = kSceneTimeOnlyEvalTools.single['function'] as Map;
      expect(only['name'], kSceneTimeTool);
      expect(only['name'], fused['name']);
    });

    test('drops posture but keeps the time fields verbatim', () {
      final fused =
          (kSceneTimeEvalTools.single['function'] as Map)['parameters'] as Map;
      final only =
          (kSceneTimeOnlyEvalTools.single['function'] as Map)['parameters']
              as Map;
      final fusedProps = fused['properties'] as Map;
      final onlyProps = only['properties'] as Map;

      expect(onlyProps.keys, isNot(contains('posture')));
      expect(
        onlyProps.keys,
        containsAll(['minutes_elapsed', 'continuous_instant', 'new_day']),
      );
      // Reused, not restated — so the two variants cannot drift apart.
      expect(onlyProps['minutes_elapsed'], same(fusedProps['minutes_elapsed']));
      expect(
        onlyProps['continuous_instant'],
        same(fusedProps['continuous_instant']),
      );
      expect(onlyProps['new_day'], same(fusedProps['new_day']));
    });
  });
}
