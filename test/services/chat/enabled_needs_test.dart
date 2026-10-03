// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pins the shared helper the fix adds (/workspace/sow/rn-spec.md item 1):
//   lib/services/chat/enabled_needs.dart
//     needsOffOf(CharacterCard?) -> List<String>
//     enabledNeedKeys(CharacterCard?) -> List<String>  (canonical order)
//     visibleNeedsFor(vector, card)  == today's visibleNeeds semantics
// Real card model + the real NeedsSimulation.needKeys / visibleNeeds as the
// oracle. On Rawhide this file does not compile (the library is missing).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart' show visibleNeeds;
import 'package:front_porch_ai/services/chat/enabled_needs.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

CharacterCard _card({List<String>? off, bool withExt = true}) => CharacterCard(
  name: 'Mara',
  firstMessage: 'Evening.',
  personality: 'calm',
  imagePath: '/tmp/rn-mara.png',
  frontPorchExtensions: withExt
      ? FrontPorchExtensions(needsSimEnabled: true, needsOff: off ?? [])
      : null,
);

void main() {
  const canonical = [
    'hunger',
    'bladder',
    'bowels',
    'energy',
    'social',
    'fun',
    'hygiene',
    'comfort',
  ];

  test('canonical order is NeedsSimulation.needKeys', () {
    expect(NeedsSimulation.needKeys, canonical);
  });

  group('enabledNeedKeys', () {
    test('null card -> all 8 in canonical order', () {
      expect(enabledNeedKeys(null), canonical);
    });

    test('card without Front Porch extensions -> all 8', () {
      expect(enabledNeedKeys(_card(withExt: false)), canonical);
    });

    test('Hygiene+Fun off -> the other 6, canonical order', () {
      expect(enabledNeedKeys(_card(off: ['hygiene', 'fun'])), [
        'hunger',
        'bladder',
        'bowels',
        'energy',
        'social',
        'comfort',
      ]);
    });

    test('off list order does not change output order', () {
      expect(
        enabledNeedKeys(_card(off: ['fun', 'hygiene'])),
        enabledNeedKeys(_card(off: ['hygiene', 'fun'])),
      );
    });

    test('all 8 off -> empty', () {
      expect(enabledNeedKeys(_card(off: List.of(canonical))), isEmpty);
    });
  });

  group('needsOffOf', () {
    test('null card -> empty', () {
      expect(needsOffOf(null), isEmpty);
    });

    test('card without extensions -> empty', () {
      expect(needsOffOf(_card(withExt: false)), isEmpty);
    });

    test('returns the card\'s needsOff', () {
      expect(needsOffOf(_card(off: ['hygiene', 'fun'])), ['hygiene', 'fun']);
    });
  });

  group('visibleNeedsFor matches today\'s visibleNeeds exactly', () {
    final vector = {
      'hunger': 58,
      'bladder': 70,
      'bowels': 70,
      'energy': 40,
      'social': 65,
      'fun': 50,
      'hygiene': 30,
      'comfort': 90,
    };

    test('empty off -> the vector as-is', () {
      // Same instance, like visibleNeeds (folded from the PR's own pin).
      expect(visibleNeedsFor(vector, _card()), same(vector));
      expect(visibleNeedsFor(vector, null), same(vector));
    });

    test('Hygiene+Fun off -> those two hidden, same as visibleNeeds', () {
      final got = visibleNeedsFor(vector, _card(off: ['hygiene', 'fun']));
      expect(got, visibleNeeds(vector, ['hygiene', 'fun']));
      expect(got.keys, ['hunger', 'bladder', 'bowels', 'energy', 'social', 'comfort']);
    });

    test('all off -> empty map, same as visibleNeeds', () {
      expect(
        visibleNeedsFor(vector, _card(off: List.of(canonical))),
        visibleNeeds(vector, canonical),
      );
    });
  });
}
