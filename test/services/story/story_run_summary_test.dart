// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/story/story.dart';

StoryRunEntry _e(String role, int seconds, {String model = ''}) =>
    StoryRunEntry(stage: 'x', role: role, millis: seconds * 1000, model: model);

void main() {
  test('time is totalled per job, in planning, prose, review order', () {
    final jobs = storyJobTimes([
      _e('review', 80, model: 'slow-thinker'),
      _e('prose', 6, model: 'quick'),
      _e('review', 100, model: 'slow-thinker'),
      _e('planning', 120, model: 'slow-thinker'),
    ]);
    expect(jobs.map((j) => j.role), ['planning', 'prose', 'review']);
    expect(
      jobs.last.line,
      'Review · 2 calls · 3 min · 90s each · slow-thinker',
    );
    expect(jobs[1].line, 'Prose · 1 call · 6s · 6s each · quick');
  });

  test('slow checks are called out once there is enough to judge', () {
    final slow = [
      for (var i = 0; i < 3; i++) ...[_e('prose', 6), _e('review', 82)],
    ];
    expect(slowChecksNote(slow), contains('Checks average 82s each'));
    expect(slowChecksNote(slow), contains('writing averages 6s'));

    // Too few calls, quick checks, or checks no slower than the writing.
    expect(slowChecksNote(slow.take(4)), isNull);
    expect(
      slowChecksNote([
        for (var i = 0; i < 3; i++) ...[_e('prose', 6), _e('review', 8)],
      ]),
      isNull,
    );
    expect(
      slowChecksNote([
        for (var i = 0; i < 3; i++) ...[_e('prose', 60), _e('review', 70)],
      ]),
      isNull,
    );
  });

  test('the model name round-trips and old entries read without one', () {
    final entry = StoryRunEntry.fromJson(
      _e('prose', 1, model: 'quick').toJson(),
    );
    expect(entry.model, 'quick');
    expect(StoryRunEntry.fromJson({'stage': 's', 'role': 'prose'}).model, '');
  });
}
