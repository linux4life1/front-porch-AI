// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Middle-delete of a give must invert THAT turn's unique moves, not
// reset live kits to the buried before-stamp (which clobbers later ops).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

Pockets kit({List<String> carrying = const []}) =>
    Pockets(carrying: [for (final n in carrying) PocketItem.clean(n)]);

void main() {
  test('inverting a give pulls the unique item off a later holder', () {
    final live = {
      'mara': kit(carrying: const []),
      'sam': kit(carrying: const []),
      'alex': kit(carrying: const ['car keys']),
    };
    invertDeletedPocketTurn(
      speakerId: 'mara',
      speakerBefore: kit(carrying: const ['car keys']),
      speakerAfter: kit(),
      othersBefore: {'sam': kit()},
      othersAfter: {
        'sam': kit(carrying: const ['car keys']),
      },
      live: live,
    );
    expect(live['mara']!.carrying.single.name, 'car keys');
    expect(live['sam']!.carrying, isEmpty);
    expect(live['alex']!.carrying, isEmpty);
  });

  test('inverting a give keeps a later unrelated pickup', () {
    final live = {
      'mara': kit(),
      'sam': kit(carrying: const ['car keys', 'sandwich']),
    };
    invertDeletedPocketTurn(
      speakerId: 'mara',
      speakerBefore: kit(carrying: const ['car keys']),
      speakerAfter: kit(),
      othersBefore: {'sam': kit()},
      othersAfter: {
        'sam': kit(carrying: const ['car keys']),
      },
      live: live,
    );
    expect(live['mara']!.carrying.single.name, 'car keys');
    expect(live['sam']!.carrying.single.name, 'sandwich');
  });

  test('pocketsStamp does not turn a missing after into an empty kit', () {
    expect(pocketsStamp(null), isNull);
    expect(pocketsStamp({'carrying': <Object?>[]}), isNotNull);
  });

  test('missing after is a no-op, not a steal from a later holder', () {
    final live = {
      'mara': kit(),
      'sam': kit(carrying: const ['car keys', 'sandwich']),
    };
    invertDeletedPocketTurn(
      speakerId: 'mara',
      speakerBefore: kit(carrying: const ['car keys']),
      speakerAfter: pocketsStamp(null),
      othersBefore: {'sam': kit()},
      othersAfter: const {},
      live: live,
    );
    expect(live['sam']!.carrying.map((i) => i.name).toList(), [
      'car keys',
      'sandwich',
    ], reason: 'a nod swipe with no pockets_after must not invert the give');
    expect(live['mara']!.carrying, isEmpty);
  });
}
