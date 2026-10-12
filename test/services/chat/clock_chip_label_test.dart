// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The body-clock chip label equals the sidebar delta: a named-time
// reconcile re-notes a counted chip but leaves Next morning alone, and
// the stall backstop snap is stamped as its own delta.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

import 'time_service_test.dart' show makeService, runEval, seedFixed;

void main() {
  test('named-time reconcile re-notes a counted chip', () async {
    final t = makeService();
    seedFixed(t, timeOfDay: 'morning');
    await runEval(t, oneShotText: '{"minutes_elapsed": 30, "new_day": false}');
    expect(t.bodyTimeLabel, '30 min');
    final named = t.clock.add(const Duration(hours: 2));
    await t.applyReconciledClock(named);
    expect(t.clock, named);
    expect(
      t.bodyTimeLabel,
      '2 hr 30 min',
      reason: 'chip must equal sidebar delta after a 2h named-time correction',
    );
  });

  test(
    'named-time reconcile leaves Next morning and skip labels alone',
    () async {
      final t = makeService();
      seedFixed(t, timeOfDay: 'night');
      await runEval(
        t,
        oneShotText: '{"minutes_elapsed": 0, "new_day": true}',
        recent: 'User: good night\nNia: sleep well, see you in the morning',
      );
      expect(t.bodyTimeLabel, 'Next morning');
      await t.applyReconciledClock(t.clock.add(const Duration(hours: 1)));
      expect(t.bodyTimeLabel, 'Next morning');
    },
  );

  test('stall backstop chip is the snap delta, not same moment', () async {
    final t = makeService();
    seedFixed(t, timeOfDay: 'morning');
    for (var i = 0; i < StoryClock.stallBackstopTurns; i++) {
      await runEval(
        t,
        oneShotText:
            '{"minutes_elapsed": 0, "new_day": false, '
            '"continuous_instant": true}',
      );
    }
    expect(t.clock, DateTime.utc(2026, 7, 2, 11, 30));
    expect(
      t.bodyTimeLabel,
      timePassedLabel(
        minutes: DateTime.utc(
          2026,
          7,
          2,
          11,
          30,
        ).difference(DateTime.utc(2026, 7, 2, 9, 0)).inMinutes,
        nextMorning: false,
        isSkip: false,
      ),
      reason: 'stall snap must not stamp same moment',
    );
  });
}
