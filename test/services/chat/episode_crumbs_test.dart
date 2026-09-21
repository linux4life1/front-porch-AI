// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clock-out crumbs and rare speech. Most shifts leave nothing.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/episode_crumbs.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';

DateTime t(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 6, day, hour, minute); // June 2026: 1=Mon

JournalMemoryData card({
  String content = 'c',
  double heat = 1.0,
  String? kind,
  String? episode,
  String? occupation,
  int? storyDay,
}) {
  final meta = <String, dynamic>{
    'kind': ?kind,
    'episode': ?episode,
    'occupation': ?occupation,
    'storyDay': ?storyDay,
  };
  return JournalMemoryData(
    id: content,
    sessionId: 's1',
    characterId: 'mara',
    content: content,
    category: 'moment',
    heat: heat,
    accessCount: 0,
    pinned: false,
    dimensions: 0,
    metadata: meta.isEmpty ? null : jsonEncode(meta),
    createdAt: DateTime(2026),
    lastAccessedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  group('clockedOutOfShift', () {
    test('9-5 Tuesday 2pm to 8pm is a clock-out', () {
      expect(
        clockedOutOfShift(
          occupation: 'librarian',
          hours: '9am–5pm',
          before: t(2, 14),
          after: t(2, 20),
        ),
        isTrue,
      );
    });

    test('9-5 Tuesday 2pm to 3pm is still on shift', () {
      expect(
        clockedOutOfShift(
          occupation: 'librarian',
          hours: '9am–5pm',
          before: t(2, 14),
          after: t(2, 15),
        ),
        isFalse,
      );
    });

    test('9-5 Tuesday 2pm to Wednesday 2pm still counts (left that shift)', () {
      expect(
        clockedOutOfShift(
          occupation: 'librarian',
          hours: '9am–5pm',
          before: t(2, 14),
          after: t(3, 14),
        ),
        isTrue,
      );
    });

    test('evening skip when they already clocked out is nothing', () {
      expect(
        clockedOutOfShift(
          occupation: 'librarian',
          hours: '9am–5pm',
          before: t(2, 18),
          after: t(2, 22),
        ),
        isFalse,
      );
    });

    test('Saturday 2pm with weekdays-only is not a clock-out', () {
      expect(
        clockedOutOfShift(
          occupation: 'librarian',
          hours: '9am–5pm',
          workDays: kDefaultWorkDays,
          before: t(6, 14), // Saturday
          after: t(6, 20),
        ),
        isFalse,
      );
    });

    test('overnight Friday 11pm to Saturday 3am clocks out', () {
      expect(
        clockedOutOfShift(
          occupation: 'bartender',
          hours: '10pm–2am',
          workDays: const [
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
          ],
          before: t(5, 23),
          after: t(6, 3),
        ),
        isTrue,
      );
    });

    test('no occupation never clocks out', () {
      expect(
        clockedOutOfShift(
          occupation: '',
          hours: '9am–5pm',
          before: t(2, 14),
          after: t(2, 20),
        ),
        isFalse,
      );
    });

    test('backward nudge is not a clock-out', () {
      expect(
        clockedOutOfShift(
          occupation: 'librarian',
          hours: '9am–5pm',
          before: t(2, 20),
          after: t(2, 14),
        ),
        isFalse,
      );
    });
  });

  group('mint roll and line', () {
    test('one in four seeds mint', () {
      expect(shouldMintWorkCrumb(0), isTrue);
      expect(shouldMintWorkCrumb(1), isFalse);
      expect(shouldMintWorkCrumb(4), isTrue);
    });

    test('same seed writes the same line', () {
      const seed = 0;
      expect(
        workCrumbContent(
          occupation: 'librarian',
          occupationBrief: 'shelves returns',
          seed: seed,
        ),
        workCrumbContent(
          occupation: 'librarian',
          occupationBrief: 'shelves returns',
          seed: seed,
        ),
      );
    });

    test('brief template is skipped when the brief is empty', () {
      for (var s = 0; s < 40; s++) {
        final line = workCrumbContent(
          occupation: 'librarian',
          occupationBrief: '',
          seed: s,
        );
        expect(line.contains('turning over this:'), isFalse);
      }
    });

    test('brief survives in a minted line when present', () {
      var sawBrief = false;
      for (var s = 0; s < 40; s++) {
        final line = workCrumbContent(
          occupation: 'librarian',
          occupationBrief: 'shelves returns',
          seed: s,
        );
        if (line.contains('shelves returns')) sawBrief = true;
      }
      expect(sawBrief, isTrue);
    });

    test('workCrumbSeed is stable', () {
      expect(
        workCrumbSeed(
          sessionId: 's',
          characterId: 'c',
          storyDay: 3,
          shiftEndMinutes: 17 * 60,
        ),
        workCrumbSeed(
          sessionId: 's',
          characterId: 'c',
          storyDay: 3,
          shiftEndMinutes: 17 * 60,
        ),
      );
    });
  });

  group('speechImpulse', () {
    test('fresh episode at full heat may be spoken', () {
      final line = speechImpulse(
        injected: [
          card(
            content:
                'I clocked out with a small argument from librarian still in my teeth.',
            heat: 1.0,
            kind: 'episode',
            episode: 'work',
          ),
        ],
        lastWords: '(OOC: six hours later)',
        seed: 1,
      );
      expect(line, contains('On their mind'));
      expect(line, contains('clocked out'));
    });

    test('old crumb without rhyme is silent', () {
      expect(
        speechImpulse(
          injected: [
            card(
              content: 'the stall with the burnt sugar',
              heat: 0.5,
              kind: 'episode',
            ),
          ],
          lastWords: 'how is the weather',
          seed: 0,
        ),
        isNull,
      );
    });

    test('old crumb that rhymes may speak on the rare roll', () {
      final line = speechImpulse(
        injected: [
          card(
            content: 'the stall with the burnt sugar',
            heat: 0.5,
            kind: 'episode',
          ),
        ],
        lastWords: 'want to get food at that stall later',
        seed: 0,
      );
      expect(line, contains('burnt sugar'));
    });

    test('old crumb that rhymes stays quiet off the rare roll', () {
      expect(
        speechImpulse(
          injected: [
            card(
              content: 'the stall with the burnt sugar',
              heat: 0.5,
              kind: 'episode',
            ),
          ],
          lastWords: 'want to get food at that stall later',
          seed: 1,
        ),
        isNull,
      );
    });
  });

  group('episode physics', () {
    test('episode cards cool at the full base rate', () {
      final c = card(kind: 'episode', episode: 'work', heat: 1.0);
      expect(JournalPhysics.isEpisodeCard(c), isTrue);
      expect(JournalPhysics.cooledHeat(c), closeTo(0.85, 1e-9));
    });

    test('work/job/shift names a work episode', () {
      final c = card(kind: 'episode', episode: 'work', occupation: 'librarian');
      expect(JournalPhysics.episodeCardMentioned(c, {'work'}), isTrue);
      expect(JournalPhysics.episodeCardMentioned(c, {'librarian'}), isTrue);
      expect(JournalPhysics.episodeCardMentioned(c, {'weather'}), isFalse);
    });

    test('one work episode per story-day', () {
      final cards = [card(kind: 'episode', episode: 'work', storyDay: 3)];
      expect(alreadyHasWorkEpisodeToday(cards: cards, storyDay: 3), isTrue);
      expect(alreadyHasWorkEpisodeToday(cards: cards, storyDay: 4), isFalse);
    });
  });
}
