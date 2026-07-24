// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the prioritized stop-sequence builder
// (docs/design/prompt-state-injection.md §5e). The load-bearing property:
// when a transport can only send the first N entries (remote providers cap
// `stop` at 4), the user-side stops and the user's custom stops must survive
// — the old insertion-ordered set + take(4) sent ONLY the first four shipped
// defaults, so custom stops and every name-stop never reached the server.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/stop_sequences.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

void main() {
  const defaults = GenerationSettings.kDefaultStopSequences;

  test('priority: user-side first, custom second, names third, defaults last',
      () {
    final stops = buildPrioritizedStops(
      configured: [...defaults, '~~END~~'],
      userName: 'Sam',
      characterNames: ['Alice', 'Bob'],
    );
    expect(stops[0], '\nUser:');
    expect(stops[1], '\nSam:');
    expect(stops[2], '~~END~~'); // custom addition outranks generated entries
    expect(stops[3], '\nAlice:');
    expect(stops[4], '\nBob:');
    // Shipped defaults (minus the already-placed \nUser:) trail the list.
    expect(stops.sublist(5), defaults.where((d) => d != '\nUser:').toList());
  });

  test('remote cap of 4 keeps the entries that matter in a big group', () {
    final stops = buildPrioritizedStops(
      configured: [...defaults, '~~END~~'],
      userName: 'Sam',
      characterNames: ['A', 'B', 'C', 'D', 'E', 'F'],
    );
    final sent = stops.take(4).toList();
    expect(sent, ['\nUser:', '\nSam:', '~~END~~', '\nA:']);
  });

  test('impersonating: no user-side stops, names still present', () {
    final stops = buildPrioritizedStops(
      configured: defaults,
      userName: 'Sam',
      impersonating: true,
      characterNames: ['Alice'],
    );
    expect(stops, isNot(contains('\nSam:')));
    expect(stops, contains('\nAlice:'));
    // \nUser: only appears via the shipped defaults at the tail, not slot 0.
    expect(stops.first, isNot('\nUser:'));
  });

  test('continue speaker is excluded so Continue can extend their message',
      () {
    final stops = buildPrioritizedStops(
      configured: defaults,
      userName: 'Sam',
      characterNames: ['Alice', 'Bob'],
      continueSpeakerName: 'Alice',
    );
    expect(stops, isNot(contains('\nAlice:')));
    expect(stops, contains('\nBob:'));
  });

  test('no duplicates when a name collides with a default or the user', () {
    final stops = buildPrioritizedStops(
      configured: defaults,
      userName: 'User', // '\nUser:' collides with priority-1 entry
      characterNames: ['User'],
    );
    expect(stops.where((s) => s == '\nUser:').length, 1);
  });

  test('empty user name adds no blank stop', () {
    final stops = buildPrioritizedStops(
      configured: defaults,
      userName: '  ',
      characterNames: ['Alice'],
    );
    expect(stops, isNot(contains('\n  :')));
    expect(stops, isNot(contains('\n:')));
  });
}
