// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// `FrontPorchExtensions.traitKit` across the web bridge
// (lib/services/web/util/realism_extensions_json.dart).
//
// The contract the inventory post-mortem (inventory_bridge_test.dart) made
// law: an omitted key keeps the base, because every web save that does not
// mention the field would otherwise wipe it. The present key goes through
// the ONE card reader — TraitKitEntry.parse — so the bridge can be neither
// gentler nor harsher than a PNG import of the same card: that is the
// difference from inventory, whose Pockets reader is permissive; a kit sent
// as junk parses to empty here exactly as it would from a mailed card.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

void main() {
  FrontPorchExtensions seeded() => FrontPorchExtensions(
    ambitions: ['open her own bakery'],
    traitKit: [
      TraitKitEntry(
        kind: 'bogey',
        text: 'bad temper',
        tier: 'established',
        pinned: true,
        linkedTo: 'reads a room',
      ),
      TraitKitEntry(kind: 'boon', text: 'steady hands'),
    ],
  );

  group('a web save that never mentions the kit keeps the base', () {
    test('the every-day payload: key absent', () {
      final back = frontPorchFromFields(const {
        'description': 'edited from a phone',
      }, base: seeded());
      expect(back.traitKit, hasLength(2));
      expect(
        back.traitKit.singleWhere((e) => e.isBogey).tier,
        'developing',
        reason: 'a pre-cap established base entry rides through capped',
      );
      expect(
        back.ambitions,
        ['open her own bakery'],
        reason:
            'the neighbouring list survives too — if this broke, the '
            'failure is the base itself, not the kit',
      );
    });

    test('an empty payload keeps it', () {
      expect(
        frontPorchFromFields(const {}, base: seeded()).traitKit,
        hasLength(2),
      );
    });
  });

  group('the full round trip', () {
    test('extensions -> json -> extensions keeps every authored part', () {
      final back = frontPorchFromFields(frontPorchToJson(seeded()));
      final bogey = back.traitKit.singleWhere((e) => e.isBogey);
      expect(bogey.text, 'bad temper');
      expect(bogey.tier, 'developing');
      expect(
        bogey.pinned,
        isTrue,
        reason:
            'the pin is half of what seeding '
            'honours — a temper that comes back un-pinned fades early',
      );
      expect(bogey.linkedTo, 'reads a room');
      expect(back.traitKit.singleWhere((e) => !e.isBogey).pinned, isFalse);
    });

    test('toJson actually emits the key when a kit exists', () {
      // Without this the round trip could pass on the base fallback alone.
      expect(frontPorchToJson(seeded()).containsKey('traitKit'), isTrue);
    });

    test('an empty kit is emitted as an explicit empty list', () {
      // The bridge's write-side contract is total: every key is always sent
      // (see the header — an OMITTED key means wipe on read, so the write
      // side never omits). The byte-identical-when-empty doctrine is the
      // CARD codec's job, pinned in test/models/trait_kit_test.dart.
      expect(frontPorchToJson(FrontPorchExtensions())['traitKit'], isEmpty);
    });

    test('a sent kit replaces wholesale, not merges', () {
      final back = frontPorchFromFields({
        'traitKit': [
          {'kind': 'boon', 'text': 'a bus ticket', 'tier': 'developing'},
        ],
      }, base: seeded());
      expect(back.traitKit, hasLength(1));
      expect(back.traitKit.single.text, 'a bus ticket');
      expect(back.traitKit.single.tier, 'developing');
    });

    test(
      'an explicit empty list clears it — "starts with nothing" is sayable',
      () {
        expect(
          frontPorchFromFields(const {'traitKit': []}, base: seeded()).traitKit,
          isEmpty,
        );
      },
    );
  });

  group('what is sent is read exactly as a card import would read it', () {
    test('the 6-entry budget truncates over the wire too', () {
      final back = frontPorchFromFields({
        'traitKit': [
          for (var i = 0; i < 9; i++) {'kind': 'boon', 'text': 'trait $i'},
        ],
      }, base: seeded());
      expect(back.traitKit, hasLength(TraitKitEntry.maxEntries));
    });

    test('junk lands empty — same as the one card reader, by contract', () {
      // Deliberately NOT the inventory rule (junk keeps the base): there is
      // one reader for this field, and its law is fail-soft to empty. The
      // editor re-reads the character after a save, so what shows is what
      // the reader honours on import from anywhere.
      for (final junk in <Object>[
        'kit',
        7,
        {'a': 1},
      ]) {
        expect(
          frontPorchFromFields({'traitKit': junk}, base: seeded()).traitKit,
          isEmpty,
          reason: 'junk: $junk',
        );
      }
    });

    test('bad entries inside a good list are dropped one by one', () {
      final back = frontPorchFromFields({
        'traitKit': [
          {'kind': 'power', 'text': 'flight'},
          {'kind': 'bogey', 'text': 'bad temper'},
          {'kind': 'bogey', 'text': 'short fuse', 'tier': 'developing'},
        ],
      });
      expect(back.traitKit, hasLength(2));
      expect(back.traitKit.first.isBogey, isTrue);
      // Tier-aware default (ruling 2026-11-21): the Novice flaw arrives
      // unpinned; the Skilled one arrives pinned.
      expect(back.traitKit.first.pinned, isFalse);
      expect(back.traitKit.last.pinned, isTrue);
    });
  });
}
