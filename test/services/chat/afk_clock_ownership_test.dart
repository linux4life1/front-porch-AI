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

import 'dart:io';

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

  test(
    'advanceTimePeriods sets skip-owns-clock before the post-reply eval',
    () {
      final src = File(
        'lib/services/chat/time_service.dart',
      ).readAsStringSync();
      final start = src.indexOf('void advanceTimePeriods');
      expect(start, greaterThanOrEqualTo(0));
      final body = src.substring(start, start + 500);
      expect(body, contains('_oocSkipMovedClockThisTurn = true'));
      final idle = File(
        'lib/services/chat/chat_service_idle_autonomous.dart',
      ).readAsStringSync();
      expect(idle, contains('advanceTimePeriods('));
      expect(
        idle.indexOf('advanceTimePeriods('),
        lessThan(idle.indexOf('_generateResponse(')),
      );
    },
  );
}
