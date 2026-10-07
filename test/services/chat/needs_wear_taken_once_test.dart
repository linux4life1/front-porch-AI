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

// The clock's wear minutes are taken once. A turn that notes no new beat
// cannot wear the last one again, and a named-time correction read from
// the reply leaves only its own extra minutes to wear (review, Needs v2).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

TimeService _clock() => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
);

Future<void> _measured(TimeService t, int minutes) =>
    t.evaluateTimeProgressAndPostureIfNeeded(
      charName: 'Nia',
      recent: 'User: hi\nNia: hello',
      shortTermTierName: 'Warm',
      onChunk: null,
      fireLLMEval: (prompt, {onChunk}) async =>
          '{"minutes_elapsed": $minutes, "new_day": false}',
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

void main() {
  test('wear minutes are taken once', () async {
    final t = _clock();
    t.seedFromV2OrExt(
      dayCount: 1,
      timeOfDay: 'morning',
      storyStartDate: '2026-08-22',
      storyStartTime: '09:00',
    );
    await _measured(t, 20);
    expect(t.bodyWearMinutes, 20);
    expect(t.takeBodyWearMinutes(), 20);
    expect(t.bodyWearMinutes, 0, reason: 'taken, so nothing to wear twice');
    expect(t.takeBodyWearMinutes(), 0);
  });

  test('a named-time correction leaves only its extra minutes', () async {
    final t = _clock();
    t.seedFromV2OrExt(
      dayCount: 1,
      timeOfDay: 'morning',
      storyStartDate: '2026-08-22',
      storyStartTime: '09:00',
    );
    await _measured(t, 20);
    expect(t.takeBodyWearMinutes(), 20, reason: 'the beat, worn first');

    // The reply then says it is ten o'clock: 40 minutes past the beat.
    await t.applyReconciledClock(DateTime.utc(2026, 8, 22, 10, 0));
    expect(t.bodyTimeLabel, '1 hr', reason: 'the chip shows the whole beat');
    expect(
      t.takeBodyWearMinutes(),
      40,
      reason: 'only the correction is still owed; the 20 were taken',
    );
  });

  test('a correction backwards owes nothing', () async {
    final t = _clock();
    t.seedFromV2OrExt(
      dayCount: 1,
      timeOfDay: 'morning',
      storyStartDate: '2026-08-22',
      storyStartTime: '09:00',
    );
    await _measured(t, 60);
    t.takeBodyWearMinutes();
    await t.applyReconciledClock(DateTime.utc(2026, 8, 22, 9, 30));
    expect(t.takeBodyWearMinutes(), 0);
  });
}
