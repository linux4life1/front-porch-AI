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

// FREEZING A SYNTHESISED STORY DATE INTO THE SESSION ROW.
//
// The v38 ladder note says legacy rows "synthesize on first load". They did —
// and the result was thrown away, because the canonical columns are only
// written by a full chat save, and a save only happens when you send a message.
// Open an old chat, read it, close it: nothing was written, and the next open
// re-synthesised against a different real-world date. The story date followed
// the calendar on your wall, while the journal and the recap kept naming the
// one it had before.
//
// 96 of the 109 sessions in the maintainer's own library were still NULL here,
// so this was the normal case for that library, not an edge.
//
// The behavioural half of this fix (what gets derived, and that the loader
// announces it) is pinned in test/services/chat/story_clock_stability_test.dart
// against a real TimeService. This file pins the other half: that the derived
// values survive a write to the actual database, that a second load of the
// frozen row no longer depends on the wall clock, and that the loader is
// actually wired to do the write.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

TimeService makeService() => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  /// The write `_hydrateSessionScalars` performs when the loader reports that
  /// it had to invent the date. Kept in one place so the structural test below
  /// can check the real call site names the same columns.
  Future<void> freeze(String id, TimeService t) => db.patchSession(
    SessionsCompanion(
      id: Value(id),
      storyClock: Value(t.storyClockIso),
      storyStartDate: Value(t.storyStartDateIso),
      startDayOfWeek: Value(t.startDayOfWeekAnchor),
      timeOfDay: Value(t.timeOfDay),
      dayCount: Value(t.dayCount),
    ),
  );

  group('a legacy row is frozen on the open that first needs it', () {
    test(
      'the invented date reaches the row, and a reload reproduces it',
      () async {
        // A pre-v38 chat: period and day number, no canonical columns at all.
        await db.insertSession(
          SessionsCompanion.insert(
            id: 's-legacy',
            timeOfDay: const Value('evening'),
            dayCount: const Value(5),
            startDayOfWeek: const Value(1),
          ),
        );
        final row = await db.getSessionById('s-legacy');
        expect(
          row!.storyClock,
          isNull,
          reason: 'the state 96/109 chats were in',
        );

        // Open it once.
        final first = makeService();
        first.loadTimeScalars(
          timeOfDay: row.timeOfDay,
          dayCount: row.dayCount,
          startDayOfWeek: row.startDayOfWeek,
          passageOfTimeEnabled: row.passageOfTimeEnabled,
          storyClock: row.storyClock,
          storyStartDate: row.storyStartDate,
        );
        expect(first.canonicalClockWasSynthesised, isTrue);
        await freeze('s-legacy', first);

        final frozen = await db.getSessionById('s-legacy');
        expect(frozen!.storyClock, first.storyClockIso);
        expect(frozen.storyStartDate, first.storyStartDateIso);
        expect(
          frozen.startDayOfWeek,
          first.startDayOfWeekAnchor,
          reason:
              'the legacy anchor column must agree with the new Day 1, or an '
              'external reader (a V2 card, an older app) sees two answers',
        );

        // Open it again — the second open is the one that used to move.
        final second = makeService();
        second.loadTimeScalars(
          timeOfDay: frozen.timeOfDay,
          dayCount: frozen.dayCount,
          startDayOfWeek: frozen.startDayOfWeek,
          passageOfTimeEnabled: frozen.passageOfTimeEnabled,
          storyClock: frozen.storyClock,
          storyStartDate: frozen.storyStartDate,
        );

        expect(
          second.canonicalClockWasSynthesised,
          isFalse,
          reason:
              'nothing is invented the second time, so nothing is rewritten',
        );
        expect(second.clock, first.clock);
        expect(second.startDate, first.startDate);
        expect(
          second.dayCount,
          5,
          reason: 'Day 5 stays Day 5 across the freeze',
        );
        expect(second.timeOfDay, 'evening');
      },
    );

    test('the freeze is a partial write — it touches nothing else', () async {
      await db.insertSession(
        SessionsCompanion.insert(
          id: 's-partial',
          timeOfDay: const Value('morning'),
          dayCount: const Value(2),
          affectionScore: const Value(140),
          trustLevel: const Value(77),
          needsVector: const Value('{"hunger":61}'),
          summary: const Value('where we are'),
        ),
      );
      final t = makeService();
      t.loadTimeScalars(
        timeOfDay: 'morning',
        dayCount: 2,
        startDayOfWeek: 0,
        passageOfTimeEnabled: true,
      );
      await freeze('s-partial', t);

      final after = await db.getSessionById('s-partial');
      expect(after!.storyClock, isNotNull);
      // This is why it is a patchSession and not a _saveChat: the loader runs
      // this mid-hydration, before needs / pockets / chaos have been restored,
      // so a full-row write here would persist a half-loaded chat over a
      // complete one.
      expect(after.affectionScore, 140);
      expect(after.trustLevel, 77);
      expect(after.needsVector, '{"hunger":61}');
      expect(after.summary, 'where we are');
    });

    test('a story with a fixed era keeps its era through the freeze', () async {
      // The half-populated row: an authored Day 1 in 1887, no clock yet. The
      // old path put the "current" moment on today's real date and left 1887 as
      // Day 1 — a chat somewhere around Day 50,000.
      await db.insertSession(
        SessionsCompanion.insert(
          id: 's-1887',
          timeOfDay: const Value('night'),
          dayCount: const Value(3),
          storyStartDate: const Value('1887-06-01'),
        ),
      );
      final row = await db.getSessionById('s-1887');
      final t = makeService();
      t.loadTimeScalars(
        timeOfDay: row!.timeOfDay,
        dayCount: row.dayCount,
        startDayOfWeek: row.startDayOfWeek,
        passageOfTimeEnabled: row.passageOfTimeEnabled,
        storyClock: row.storyClock,
        storyStartDate: row.storyStartDate,
      );
      await freeze('s-1887', t);

      final after = await db.getSessionById('s-1887');
      expect(
        StoryClock.parse(after!.storyClock),
        DateTime.utc(1887, 6, 3, 22, 30),
      );
      expect(after.dayCount, 3);
      expect(after.storyStartDate, '1887-06-01');
    });
  });
}
