// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AFK snaps the clock by the away pace, then generates a reply. The
// post-reply time eval used to add minutes on top of that snap because
// advanceTimePeriods never set the skip-owns-clock flag OOC skip uses.
//
// Proven red: without _oocSkipMovedClockThisTurn = true in
// advanceTimePeriods, applyFailureDrift (the same consume-the-flag path
// the eval uses) adds failureDriftMinutes after the snap.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

TimeService _clock() => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
);

void main() {
  test(
    'AFK period advance owns the clock so post-reply drift cannot add more',
    () async {
      final t = _clock();
      t.seedFromV2OrExt(
        dayCount: 1,
        timeOfDay: 'morning',
        passageOfTimeEnabled: true,
        storyStartDate: '2026-07-02',
        storyStartTime: '09:00',
      );
      t.advanceTimePeriods(1);
      final afterAfk = t.clock;
      expect(afterAfk, isNot(DateTime.utc(2026, 7, 2, 9, 0)));
      await t.applyFailureDrift();
      expect(
        t.clock,
        afterAfk,
        reason:
            'THE BUG: AFK snap did not own the turn, so the post-reply '
            'eval/drift stacked minutes on the away pace',
      );
    },
  );
}
