// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A finished night lands before they write. Going to bed is still a scene.
// The skip reader (a model) decides what a line means; these pin the wide
// net in front of it and the date math behind it.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/time_skip/time_skip.dart';

TimeService _clock() => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
);

void main() {
  final evening = DateTime.utc(2026, 8, 22, 20, 31);

  group('the wide net', () {
    test('a night, hours and an OOC skip are worth asking about', () {
      expect(mightSkipTime('We sleep through the night.'), isTrue);
      expect(mightSkipTime('(OOC: everyone sleeps for eight hours)'), isTrue);
      expect(mightSkipTime('*Two weeks later, the porch is quiet.*'), isTrue);
      expect(mightSkipTime('The next morning, sunlight.'), isTrue);
      expect(mightSkipTime('Fast forward to 7:30.'), isTrue);
    });

    test('an ordinary line costs no call', () {
      expect(mightSkipTime('*She sits down next to him and smiles.*'), isFalse);
      expect(mightSkipTime('I pass you the salt.'), isFalse);
    });

    test('time words inside quoted speech are not narration', () {
      expect(
        mightSkipTime('"We sleep through the night," she joked.'),
        isFalse,
      );
    });
  });

  group('clock landing', () {
    test('a night slept through lands at next morning', () {
      expect(
        const SkipVerdict(until: 'morning', slept: true).landing(evening),
        DateTime.utc(2026, 8, 23, 8, 0),
      );
    });

    test('a counted span is exact, whatever the line says of morning', () {
      // #629: "slept eight hours and woke up" landed at 8 AM, five hours.
      final small = DateTime.utc(2026, 8, 22, 1, 40);
      expect(
        const SkipVerdict(minutes: 480, until: 'morning').landing(small),
        DateTime.utc(2026, 8, 22, 9, 40),
      );
    });

    test('days land on their day, in the morning or where they say', () {
      expect(
        const SkipVerdict(minutes: 14 * 1440).landing(evening),
        DateTime.utc(2026, 9, 5, 9, 0),
      );
      expect(
        const SkipVerdict(minutes: 2 * 1440, until: 'evening').landing(evening),
        DateTime.utc(2026, 8, 24, 18, 30),
      );
    });

    test('applyUserSkip moves 8:31pm to 8am', () async {
      final t = _clock();
      t.seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'evening',
        storyStartDate: '2026-08-22',
        storyStartTime: '20:31',
      );
      expect(t.clock.hour, 20);
      await t.applyUserSkip(const SkipVerdict(until: 'morning', slept: true));
      expect(t.clock, DateTime.utc(2026, 8, 23, 8, 0));
      expect(t.dayCount, 2);
      // Needs v2: the night is a span the body wears, off-screen (floors).
      expect(t.bodyWearMinutes, 11 * 60 + 29);
      expect(t.bodyBeatOffScreen, isTrue);
    });

    test('a measured reply wears those minutes', () async {
      final t = _clock();
      await t.evaluateTimeProgressAndPostureIfNeeded(
        charName: 'Nia',
        recent: 'User: hi\nNia: hello',
        shortTermTierName: 'Warm',
        onChunk: null,
        fireLLMEval: (prompt, {onChunk}) async =>
            '{"minutes_elapsed": 90, "new_day": false}',
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
      // Needs v2: the clock charges the span (needs_wear.dart), on-screen.
      expect(t.bodyWearMinutes, 90);
      expect(t.bodyBeatOffScreen, isFalse);
      expect(t.bodyTimeLabel, '1 hr 30 min');
    });

    test('time away wears its span off-screen', () {
      final t = _clock();
      t.advanceTimePeriods(1);
      expect(t.bodyWearMinutes, greaterThan(0));
      expect(t.bodyBeatOffScreen, isTrue);
      expect(t.bodyTimeLabel, isNotNull);
    });

    test("no skip read from let's go to bed leaves the clock", () async {
      final t = _clock();
      t.seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'evening',
        storyStartDate: '2026-08-22',
        storyStartTime: '20:31',
      );
      expect(await t.applyUserSkip(SkipVerdict.none), 0);
      expect(t.clock.hour, 20);
    });
  });

  group('the /skip tag', () {
    SkipVerdict? read(String text) => SkipTag.parse(text).verdict;

    test('the tag comes off the line and gives the exact skip', () {
      final tag = SkipTag.parse('I wait on the steps. /skip 8h');
      expect(tag.body, 'I wait on the steps.');
      expect(tag.verdict, const SkipVerdict(minutes: 480));
      expect(read('/skip 1d 6h'), const SkipVerdict(minutes: 30 * 60));
      expect(read('/skip 8 hours'), const SkipVerdict(minutes: 480));
      expect(read('/skip 90 min'), const SkipVerdict(minutes: 90));
      expect(
        read('/skip 2 weeks morning'),
        const SkipVerdict(minutes: 14 * 24 * 60, until: 'morning'),
      );
    });

    test('it lands on a period or a clock time', () {
      expect(
        read('/skip late morning'),
        const SkipVerdict(until: 'late_morning'),
      );
      expect(read('/skip noon'), const SkipVerdict(until: '12:00'));
      expect(read('/skip 7:30 pm'), const SkipVerdict(until: '19:30'));
      expect(read('/skip 7am'), const SkipVerdict(until: '07:00'));
      expect(read('/skip 07:30'), const SkipVerdict(until: '07:30'));
    });

    test('a tag it cannot read says how to use it; no tag is no skip', () {
      expect(SkipTag.parse('Tea? /skip 8 parsecs').error, kSkipTagUsage);
      expect(SkipTag.parse('/skip').error, kSkipTagUsage);
      expect(SkipTag.parse('/skip 7').error, kSkipTagUsage);
      for (final prose in [
        'I tap /skip on the ad and keep reading.',
        'Tea? /skip soonish',
        'I hit /skip',
      ]) {
        final tag = SkipTag.parse(prose);
        expect(tag.present, isFalse, reason: prose);
        expect(tag.body, prose);
      }
      final none = SkipTag.parse('We were /skipping stones.');
      expect(none.present, isFalse);
      expect(none.body, 'We were /skipping stones.');
    });
  });

  group('the skip reader', () {
    test(
      'its JSON reads as a skip, no skip, an unmeasured skip or nothing',
      () {
        expect(
          SkipVerdict.fromJsonText(
            '<think>hm</think>{"skip": true, "minutes": 480, "until": "", '
            '"gap": "slept"}',
          ),
          const SkipVerdict(minutes: 480, slept: true),
        );
        expect(SkipVerdict.fromJsonText('{"skip": false}'), SkipVerdict.none);
        expect(
          SkipVerdict.fromJsonText(
            '{"skip": true, "minutes": 0, "until": "", "gap": "other"}',
          )!.isUnmeasured,
          isTrue,
        );
        expect(SkipVerdict.fromJsonText('Yes, they skip.'), isNull);
        expect(SkipVerdict.fromJsonText('{"minutes": 30}'), isNull);
      },
    );

    test('a reader that fails reads nothing', () async {
      final reader = SkipReader(
        fireLLMEval: (_) async => throw StateError('backend down'),
        stripThinkBlocks: (t) => t,
      );
      expect(await reader.read(line: 'We sleep.', clock: evening), isNull);
    });

    PlayerSkip skipper(TimeService t, String? answer, List<String> asked) =>
        PlayerSkip(
          time: t,
          reader: SkipReader(
            fireLLMEval: (p) async {
              asked.add(p);
              return answer;
            },
            stripThinkBlocks: (t) => t,
          ),
        );

    TimeService running() => _clock()
      ..seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'evening',
        storyStartDate: '2026-08-22',
        storyStartTime: '20:31',
      )
      ..setPassageOfTimeEnabled(true);

    test('only a line with time words is read, and an answer that is no '
        'answer moves nothing', () async {
      final t = running();
      final asked = <String>[];
      expect(await skipper(t, 'Sure!', asked).apply('I pass the salt.'), 0);
      expect(asked, isEmpty);
      expect(await skipper(t, 'Sure!', asked).apply('We sleep.'), 0);
      expect(asked, hasLength(1));
      expect(t.clock, DateTime.utc(2026, 8, 22, 20, 31));
    });

    test('a skip with no amount moves an hour; /skip keeps the reader\'s '
        'sleep but its own amount', () async {
      final t = running();
      final unmeasured =
          '{"skip": true, "minutes": 0, "until": "", "gap": "other"}';
      expect(
        await skipper(t, unmeasured, []).apply('Some time passes.'),
        kUnmeasuredSkipMinutes,
      );
      final slept =
          '{"skip": true, "minutes": 600, "until": "", "gap": "slept"}';
      final verdict = await skipper(
        t,
        slept,
        [],
      ).decide('We sleep.', exact: const SkipVerdict(minutes: 480));
      expect(verdict, const SkipVerdict(minutes: 480, slept: true));
    });

    test('a chat that changed under the read keeps its clock', () async {
      final t = running();
      final reading =
          '{"skip": true, "minutes": 480, "until": "", "gap": "other"}';
      final moved = await skipper(
        t,
        reading,
        [],
      ).apply('Eight hours later.', stale: () => true);
      expect(moved, 0);
      expect(t.clock, DateTime.utc(2026, 8, 22, 20, 31));
    });

    test('with Passage of Time off nothing is read', () async {
      final t = running()..setPassageOfTimeEnabled(false);
      final asked = <String>[];
      expect(await skipper(t, '{}', asked).decide('We sleep.'), isNull);
      expect(asked, isEmpty);
    });
  });

  group('the "Did time pass?" pop-up', () {
    TimeService at(String hhmm, String period) => _clock()
      ..seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: period,
        storyStartDate: '2026-08-22',
        storyStartTime: hhmm,
      )
      ..setPassageOfTimeEnabled(true);

    PlayerSkip skipper(TimeService t, String? answer) => PlayerSkip(
      time: t,
      reader: SkipReader(
        fireLLMEval: (_) async => answer,
        stripThinkBlocks: (t) => t,
      ),
    );

    String reading(int minutes, {String until = '', bool slept = false}) =>
        '{"skip": true, "minutes": $minutes, "until": "$until", '
        '"gap": "${slept ? 'slept' : 'other'}"}';

    test('a count that disagrees with the reading asks, and the '
        'player\'s eight hours land at 9:40', () async {
      final t = at('01:40', 'night');
      final asked = <PendingSkip>[];
      final moved = await skipper(t, reading(0, until: 'morning', slept: true))
          .apply(
            '*We fell asleep on the couch and slept eight hours before we '
            'woke up.*',
            ask: (q) async {
              asked.add(q);
              return q.choices[1].verdict;
            },
          );
      expect(asked.single.reason, SkipAskReason.disagrees);
      expect(
        [for (final c in asked.single.choices) c.label],
        ['Next morning · 8:00 AM', '8 hours · 9:40 AM'],
      );
      expect(asked.single.question, contains("It's 1:40 AM now."));
      expect(moved, 480);
      expect(t.clock, DateTime.utc(2026, 8, 22, 9, 40));
    });

    test(
      'a short reading the count agrees with applies without asking',
      () async {
        final t = at('20:31', 'evening');
        var asked = 0;
        final moved = await skipper(t, reading(480)).apply(
          '*Eight hours later, the rain stops.*',
          ask: (_) async {
            asked++;
            return null;
          },
        );
        expect(asked, 0);
        expect(moved, 480);
      },
    );

    test('a day or more asks; no answer keeps the reader\'s guess', () async {
      final t = at('20:31', 'evening');
      final asked = <PendingSkip>[];
      final verdict = await skipper(t, reading(14 * 24 * 60)).decide(
        '*Two weeks later, I knock on her door again.*',
        ask: (q) async {
          asked.add(q);
          return null;
        },
      );
      expect(asked.single.reason, SkipAskReason.long);
      expect(asked.single.choices.first.label, '2 weeks · Sat, Sep 5, 9:00 AM');
      expect(verdict, const SkipVerdict(minutes: 14 * 24 * 60));
    });

    test(
      'a failed reader asks with no guess, and "no skip" moves nothing',
      () async {
        final t = at('20:31', 'evening');
        final asked = <PendingSkip>[];
        final moved = await skipper(t, null).apply(
          'We sleep.',
          ask: (q) async {
            asked.add(q);
            return SkipVerdict.none;
          },
        );
        expect(asked.single.reason, SkipAskReason.noReading);
        expect(
          [for (final c in asked.single.choices) c.label],
          ['Next morning · Sun, Aug 23, 8:00 AM', '1 hour · 9:31 PM'],
        );
        expect(moved, 0);
        expect(t.clock, DateTime.utc(2026, 8, 22, 20, 31));
      },
    );

    test('a skip with no amount asks, its hour offered first', () async {
      final t = at('20:31', 'evening');
      final asked = <PendingSkip>[];
      await skipper(t, reading(0)).decide(
        'Some time passes.',
        ask: (q) async {
          asked.add(q);
          return null;
        },
      );
      expect(asked.single.reason, SkipAskReason.noAmount);
      expect(asked.single.choices.first.label, '1 hour · 9:31 PM');
    });

    test('an exact /skip and a reading of no skip never ask', () async {
      final t = at('20:31', 'evening');
      var asked = 0;
      Future<SkipVerdict?> ask(PendingSkip _) async {
        asked++;
        return SkipVerdict.none;
      }

      expect(
        await skipper(t, reading(3 * 24 * 60)).decide(
          'We sleep.',
          exact: const SkipVerdict(minutes: 2 * 24 * 60),
          ask: ask,
        ),
        const SkipVerdict(minutes: 2 * 24 * 60),
      );
      expect(
        await skipper(
          t,
          '{"skip": false}',
        ).decide('See you in two weeks.', ask: ask),
        SkipVerdict.none,
      );
      expect(asked, 0);
    });

    test('"Other…" reads like the /skip tag', () {
      expect(SkipTag.readArgs(' 8h '), const SkipVerdict(minutes: 480));
      expect(SkipTag.readArgs('Morning'), const SkipVerdict(until: 'morning'));
      expect(SkipTag.readArgs('soonish'), isNull);
    });

    test('the count reads one span of narration, never speech', () {
      expect(countedSkipMinutes('*Three hours pass.*'), 180);
      expect(countedSkipMinutes('Two weeks later, I knock.'), 20160);
      expect(countedSkipMinutes('"See you in two weeks." I nap.'), isNull);
      expect(countedSkipMinutes('A day and eight hours pass.'), isNull);
      expect(countedSkipMinutes('We sleep.'), isNull);
    });

    test('the gate holds one question; a new one drops the old', () async {
      final gate = SkipConfirmGate();
      expect(gate.answer(SkipVerdict.none), isFalse);
      final q = PendingSkip.build(
        line: 'We sleep.',
        reason: SkipAskReason.noReading,
        clock: DateTime.utc(2026, 8, 22, 20, 31),
      );
      final first = gate.ask(q);
      expect(gate.pending, same(q));
      final second = gate.ask(q);
      expect(await first, isNull);
      expect(gate.answer(const SkipVerdict(minutes: 60)), isTrue);
      expect(await second, const SkipVerdict(minutes: 60));
      expect(gate.pending, isNull);
    });
  });
}
