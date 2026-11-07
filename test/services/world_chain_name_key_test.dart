// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The ONE place-name collision key (world_chain.placeNameKey): the chat
// mint redirect and the PlaceFactory refusal both match through it and
// nothing else, so the two seams can never disagree about what counts as
// "that place already exists". Proven red: without whitespace folding a
// model-proposed "salt  GARDEN" minted beside a hand-made "Salt Garden".

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/world_chain.dart';

void main() {
  group('placeNameKey', () {
    test('trims, folds case, and collapses whitespace runs', () {
      const key = 'warmward guest chamber';
      expect(placeNameKey('Warmward Guest Chamber'), key);
      expect(placeNameKey('  warmward  guest  chamber  '), key);
      expect(placeNameKey('WARMWARD\tguest\nchamber'), key);
    });

    test('different names keep different keys', () {
      expect(
        placeNameKey('Salt Garden') == placeNameKey('Salt Gardens'),
        isFalse,
      );
      expect(
        placeNameKey('Guest Chamber') == placeNameKey('Guest Room'),
        isFalse,
      );
    });

    test('a blank and a whitespace-only name share the empty key', () {
      expect(placeNameKey(''), placeNameKey('   \t '));
    });
  });
}
