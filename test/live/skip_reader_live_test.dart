// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The skip reader against a REAL model: the prompt the app sends, the
// phrasings players write (#629 among them), and the reading the clock
// would take. The unit suites give the reader fixed readings; this is the
// pin that the words mean what those readings say. Never a fake model
// (CLAUDE.md ## Tests). Skips unless the provider is named, so the default
// run and CI are unaffected.
//
//   FPAI_LIVE_API_URL=http://localhost:5001/v1 FPAI_LIVE_MODEL=<id> \
//     flutter test --tags live test/live/skip_reader_live_test.dart
//
// FPAI_LIVE_API_KEY names the provider key when it needs one.

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/time_skip/time_skip.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

/// flutter_test stubs HttpClient to 400; this restores the real client.
class _RealHttpOverrides extends HttpOverrides {}

String? _env(String key) {
  final v = Platform.environment[key]?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apiUrl = _env('FPAI_LIVE_API_URL');
  final model = _env('FPAI_LIVE_MODEL');
  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = _RealHttpOverrides());
  tearDown(() => HttpOverrides.global = savedOverrides);

  final clock = DateTime.utc(2026, 8, 22, 1, 40);

  Future<SkipVerdict?> read(String line) {
    final llm = OpenRouterService(
      apiUrl: apiUrl!,
      apiKey: _env('FPAI_LIVE_API_KEY') ?? '',
      modelName: model!,
    );
    final reader = SkipReader(
      fireLLMEval: (prompt) => llm
          .generateStream(
            GenerationParams(prompt: prompt, maxLength: 400, temperature: 0),
          )
          .join(),
      stripThinkBlocks: stripThinkBlocks,
    );
    return reader.read(line: line, clock: clock);
  }

  void live(String name, String line, void Function(SkipVerdict) check) {
    test(name, () async {
      if (apiUrl == null || model == null) {
        markTestSkipped('FPAI_LIVE_API_URL / FPAI_LIVE_MODEL not set');
        return;
      }
      final verdict = await read(line);
      expect(verdict, isNotNull, reason: 'no usable answer for: $line');
      check(verdict!);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  live(
    '#629: slept eight hours and woke up is eight hours, slept',
    '*We fell asleep on the couch and slept eight hours before we woke up.*',
    (v) {
      expect(v.minutes, 480);
      expect(v.slept, isTrue);
      expect(v.landing(clock), DateTime.utc(2026, 8, 22, 9, 40));
    },
  );

  live(
    'an OOC skip to the morning lands in the morning',
    '(OOC: skip to '
        'the next morning)',
    (v) {
      final at = v.landing(clock)!;
      expect(at.day, anyOf(22, 23));
      expect(at.hour, inInclusiveRange(6, 11));
    },
  );

  live(
    'two weeks later is two weeks',
    '*Two weeks later, I knock on her '
        'door again.*',
    (v) {
      expect(v.minutes, 14 * 24 * 60);
      expect(v.slept, isFalse);
    },
  );

  live(
    'hours in words are counted',
    '*Three hours pass in comfortable '
        'silence.*',
    (v) => expect(v.minutes, 180),
  );

  live('a clock time is where it lands', '(OOC: fast forward to 7:30 pm)', (v) {
    expect(v.landing(clock), DateTime.utc(2026, 8, 22, 19, 30));
  });

  live('a plan to sleep is not a skip', "Let's get some sleep soon.", (v) {
    expect(v.isSkip, isFalse);
  });

  live(
    'a memory is not a skip',
    'I tell her we met two weeks ago at the '
        'market.',
    (v) => expect(v.isSkip, isFalse),
  );

  live(
    'see you tomorrow is not a skip',
    'See you tomorrow, then. *I wave '
        'from the gate.*',
    (v) => expect(v.isSkip, isFalse),
  );

  live(
    'a skip a character says is not a skip',
    '*I stretch, still sleepy.* "Will you post the video next week?"',
    (v) => expect(v.isSkip, isFalse),
  );

  // The after-reply scene-time judge, through the app's own prompt and
  // parse, on replies that jump hours, days, a night, or nothing.
  group('the scene-time judge', () {
    Future<TimeService> judge(String reply) async {
      final llm = OpenRouterService(
        apiUrl: apiUrl!,
        apiKey: _env('FPAI_LIVE_API_KEY') ?? '',
        modelName: model!,
      );
      final t =
          TimeService(
            onNotify: () {},
            onSaveChat: () async {},
            onSetPendingRealismMetadata: (_, _) {},
            onPatchLastMessageRealismState: (_, _, _) {},
          )..seedFromV2OrExt(
            dayCount: 1,
            timeOfDay: 'night',
            storyStartDate: '2026-08-22',
            storyStartTime: '22:00',
          );
      t.setPassageOfTimeEnabled(true);
      await t.evaluateTimeProgressAndPostureIfNeeded(
        charName: 'Mae',
        recent: 'User: I sit down next to her.\nMae: $reply',
        shortTermTierName: 'Warm',
        onChunk: null,
        fireLLMEval: (p, {onChunk}) => llm
            .generateStream(
              GenerationParams(prompt: p, maxLength: 400, temperature: 0),
            )
            .join(),
        stripThinkBlocks: stripThinkBlocks,
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
      return t;
    }

    final from = DateTime.utc(2026, 8, 22, 22);

    void judged(String name, String reply, void Function(TimeService) check) {
      test(name, () async {
        if (apiUrl == null || model == null) {
          markTestSkipped('FPAI_LIVE_API_URL / FPAI_LIVE_MODEL not set');
          return;
        }
        check(await judge(reply));
      }, timeout: const Timeout(Duration(minutes: 3)));
    }

    judged(
      'six hours later is six hours',
      '*Six hours later, the rain finally stops.*',
      (t) => expect(t.clock, from.add(const Duration(hours: 6))),
    );

    judged(
      'three days later, that evening lands three days on, in the evening',
      '*Three days later, that evening, she knocks at last.*',
      (t) {
        expect(t.clock.day, 25);
        expect(t.clock.hour, inInclusiveRange(17, 20));
      },
    );

    judged(
      'a night slept through lands in the morning, rested',
      '*She falls asleep against your shoulder, and you both sleep until '
          'the morning light wakes you.*',
      (t) {
        expect(t.clock.day, 23);
        expect(t.clock.hour, inInclusiveRange(6, 11));
        expect(t.bodyBeatSlept, isTrue);
      },
    );

    judged(
      '"see you later" is an ordinary turn',
      '"I\'ll see you later, then," *she says, and smiles.*',
      (t) => expect(t.clock.difference(from).inMinutes, lessThanOrEqualTo(180)),
    );
  });
}
