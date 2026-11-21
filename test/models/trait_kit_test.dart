// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// `TraitKitEntry` and the card kit field — parse rules (§4), the codec's
// additive key, and the Stoop-facing fail-soft promise: a card can arrive
// from anywhere, and the kit never argues about it.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/models/character/front_porch_extensions_codec.dart';

Map<String, dynamic> _realismOf(FrontPorchExtensions e) =>
    encodeFrontPorchExtensions(e)['realism_engine'] as Map<String, dynamic>;

FrontPorchExtensions _roundTrip(FrontPorchExtensions e) =>
    decodeFrontPorchExtensions(encodeFrontPorchExtensions(e));

void main() {
  group('parse — one reader for cards from anywhere', () {
    test('a good kit survives untouched', () {
      final kit = TraitKitEntry.parse([
        {
          'kind': 'boon',
          'text': 'reads a room in one breath',
          'tier': 'established',
        },
        {
          'kind': 'bogey',
          'text': 'bad temper',
          'tier': 'developing',
          'pinned': false,
        },
      ]);
      expect(kit, hasLength(2));
      expect(kit[0].kind, 'boon');
      expect(kit[0].tier, 'established');
      expect(kit[0].pinned, isFalse, reason: 'boons default unpinned');
      expect(kit[1].isBogey, isTrue);
      expect(
        kit[1].pinned,
        isFalse,
        reason:
            'an explicit false beats the '
            'bogey default — the author unticked it on purpose',
      );
    });

    test('unknown kind and blank text are dropped, bad tier falls back', () {
      final kit = TraitKitEntry.parse([
        {'kind': 'power', 'text': 'flight'},
        {'kind': 'boon', 'text': '   '},
        {'kind': 'boon', 'text': 'steady hands', 'tier': 'royal'},
        {'kind': 'bogey', 'text': 7},
      ]);
      expect(kit, hasLength(1));
      expect(kit.single.text, 'steady hands');
      expect(kit.single.tier, 'emerging', reason: 'the weakest, safest start');
    });

    test('over-long text truncates — the idea survives a paste', () {
      final kit = TraitKitEntry.parse([
        {'kind': 'boon', 'text': 'x' * 200},
      ]);
      expect(kit.single.text.length, TraitKitEntry.maxTextChars);
    });

    test('the count is truncated to the budget, never thrown away', () {
      final kit = TraitKitEntry.parse([
        for (var i = 0; i < 9; i++) {'kind': 'boon', 'text': 'trait $i'},
      ]);
      expect(kit, hasLength(TraitKitEntry.maxEntries));
      expect(kit.last.text, 'trait ${TraitKitEntry.maxEntries - 1}');
    });

    test('junk of every shape yields an empty kit, never a throw', () {
      for (final junk in <Object?>[
        null,
        'kit',
        7,
        {},
        [42],
        [null],
      ]) {
        expect(() => TraitKitEntry.parse(junk), returnsNormally);
        expect(TraitKitEntry.parse(junk), isEmpty, reason: 'junk: $junk');
      }
    });

    test('linkedTo rides through and blank drops to null', () {
      final kit = TraitKitEntry.parse([
        {'kind': 'bogey', 'text': 'bad temper', 'linkedTo': 'reads a room'},
        {'kind': 'bogey', 'text': 'another', 'linkedTo': '  '},
      ]);
      expect(kit[0].linkedTo, 'reads a room');
      expect(kit[1].linkedTo, isNull);
    });
  });

  group('the card codec', () {
    test('a written kit round-trips through encode/decode', () {
      final e = FrontPorchExtensions(
        traitKit: [
          const TraitKitEntry(
            kind: 'bogey',
            text: 'bad temper',
            tier: 'established',
            pinned: true,
            linkedTo: 'reads a room',
          ),
          const TraitKitEntry(kind: 'boon', text: 'steady hands'),
        ],
      );
      final back = _roundTrip(e);
      expect(back.traitKit, hasLength(2));
      expect(back.traitKit[0].kind, 'bogey');
      expect(back.traitKit[0].tier, 'established');
      expect(back.traitKit[0].pinned, isTrue);
      expect(back.traitKit[0].linkedTo, 'reads a room');
      expect(back.traitKit[1].pinned, isFalse);
    });

    test('an empty kit writes no key at all', () {
      // The additive-key doctrine: pre-feature cards must stay
      // byte-identical through a re-save, which the two card goldens check.
      expect(
        _realismOf(FrontPorchExtensions()).containsKey('traitKit'),
        isFalse,
      );
      expect(
        jsonEncode(
          encodeFrontPorchExtensions(FrontPorchExtensions()),
        ).contains('traitKit'),
        isFalse,
      );
    });

    test('decode of a keyless blob is an empty kit, never null', () {
      expect(_roundTrip(FrontPorchExtensions()).traitKit, isEmpty);
    });

    test('a smuggled oversized kit is truncated on decode', () {
      final dirty = {
        'realism_engine': {
          'traitKit': [
            for (var i = 0; i < 10; i++) {'kind': 'boon', 'text': 't $i'},
          ],
        },
      };
      expect(
        decodeFrontPorchExtensions(dirty).traitKit,
        hasLength(TraitKitEntry.maxEntries),
      );
    });
  });

  group('the model API', () {
    test('toJson writes every authored part, linkedTo only when set', () {
      const e = TraitKitEntry(kind: 'boon', text: 'steady hands');
      expect(e.toJson(), {
        'kind': 'boon',
        'text': 'steady hands',
        'tier': 'emerging',
        'pinned': false,
      });
    });

    test('kindLabel is the one display word editors and Stoop share', () {
      const boon = TraitKitEntry(kind: 'boon', text: 'x');
      const bogey = TraitKitEntry(kind: 'bogey', text: 'x');
      expect(boon.kindLabel, 'Boon');
      expect(bogey.kindLabel, 'Bogey');
    });
  });
}
