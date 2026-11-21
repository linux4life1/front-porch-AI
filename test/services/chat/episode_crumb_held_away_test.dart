// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The clock-out crumb consults the Away hold (docs/design/held-away-
// presence-reads.md, H1): a member the chat holds Away is not at work,
// so a commit that crosses their clock-out mints them no "shift just
// ended" episode card. The unheld twin still mints — the hold speaks
// only when it actually holds.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

import '../../helpers/reprocess_needs_harness.dart';

bool _workCrumb(JournalMemoryData c) =>
    c.category == 'moment' &&
    (c.metadata?.contains('"episode":"work"') ?? false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    await h.storage.memorySettings.setJournalEnabled(true);
  });
  tearDown(() => h.dispose());

  /// Mint (or try to) across a 9am–5pm clock-out on day 1 of the story,
  /// with the hold answered by [held]. Returns the cards the journal kept
  /// for this mint's owner.
  Future<List<JournalMemoryData>> crossClockOut({required bool held}) async {
    await h.oneToOneWithStampedReply(needsCard('Mae'));
    final sid = h.chat.currentSessionId!;
    final start = h.chat.timeService.startDate;
    late String owner;
    for (var i = 0; ; i++) {
      owner = 'held-crumb-$held-$i';
      final seed = workCrumbSeed(
        sessionId: sid,
        characterId: owner,
        storyDay: StoryClock.dayCountFor(start, start),
        shiftEndMinutes: shiftEndMinutesOf('9am-5pm'),
      );
      if (shouldMintWorkCrumb(seed)) break;
    }
    final minter = EpisodeCrumbMinter(
      clockRunning: () => true,
      memorySettings: () => h.storage.memorySettings,
      currentSessionId: () => sid,
      cast: () => [needsCard('Mae')],
      time: () => h.chat.timeService,
      history: SessionHistoryWindow(),
      messageCount: () => h.chat.messages.length,
      workFieldsFor: (_) => (
        occupation: 'the bakery',
        hours: '9am-5pm',
        occupationBrief: '',
        workDays: const [1, 2, 3, 4, 5, 6, 7],
      ),
      characterIdFor: (_) => owner,
      journalStore: () => h.chat.journalStore,
      heldAwayFor: (_) => held,
    );
    final day1 = DateTime.utc(start.year, start.month, start.day);
    await minter.maybeMint(
      day1.add(const Duration(hours: 10)),
      day1.add(const Duration(hours: 18)),
    );
    return h.chat.journalStore.cardsFor(sid, owner);
  }

  test(
    'a held member crossing their clock-out mints no shift-end crumb',
    () async {
      final cards = await crossClockOut(held: true);
      expect(
        cards.where(_workCrumb),
        isEmpty,
        reason:
            'THE BUG: the minter checked the shift and never the hold, '
            'so a member every other read says is Away got a journal '
            'card claiming her shift just ended',
      );
    },
  );

  test('the unheld twin still mints the crumb (the hold speaks only when '
      'it holds)', () async {
    final cards = await crossClockOut(held: false);
    expect(cards.where(_workCrumb), hasLength(1));
  });
}
