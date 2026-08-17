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

// Likes & Dislikes must SURVIVE both wires, and neither is hypothetical:
//
//   1. The card wire (CharacterCard.toJson / fromJson) — what ships in the PNG
//      and to The Stoop.
//   2. The web bridge (realism_extensions_json.dart) — what the web editor
//      reads and writes.
//
// The second is the one that has actually failed. When Ambitions became a chip
// editor, the bridge did not round-trip `ambitions` at all, so the web could
// neither read nor write them and the field silently vanished on any web save.
// Adding four more phrase lists to the same bridge without a guard would be
// asking for the same bug four more times.
//
// Cards also arrive from ANYWHERE — a PNG someone mailed you, a Stoop download,
// hand-edited JSON — so the malformed cases here are the real point, not
// padding. A wrong-typed field must yield an empty list, never throw and fail
// the whole import.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/web/util/realism_extensions_json.dart';

FrontPorchExtensions seeded() => FrontPorchExtensions(
  likes: ['being read to', 'thunderstorms'],
  dislikes: ['being interrupted'],
  intimateInto: ['slow mornings'],
  intimateNotInto: ['an audience'],
  ambitions: ['open her own bakery'],
  planLines: ['finish the log before the tide'],
);

void main() {
  group('the card wire', () {
    test('all four lists survive toJson -> fromJson', () {
      final back = FrontPorchExtensions.fromJson(seeded().toJson());
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.dislikes, ['being interrupted']);
      expect(back.intimateInto, ['slow mornings']);
      expect(back.intimateNotInto, ['an audience']);
      expect(back.ambitions, ['open her own bakery'], reason: 'not regressed');
      expect(back.planLines, ['finish the log before the tide']);
    });

    test('plan_lines omitted JSON reads as empty, not null', () {
      final back = FrontPorchExtensions.fromJson(const {'realism_engine': {}});
      expect(back.planLines, isEmpty);
    });

    test('plan_lines survive the card wire', () {
      final ext = FrontPorchExtensions(
        planLines: ['finish the log before the tide'],
      );
      final json = ext.toJson();
      final realism = json['realism_engine'] as Map<String, dynamic>;
      expect(realism['plan_lines'], ['finish the log before the tide']);
      expect(
        FrontPorchExtensions.fromJson(json).planLines,
        ['finish the log before the tide'],
      );
    });

    test('the 18+ pair travels nested, so a share can strip it as one object', () {
      final realism =
          seeded().toJson()['realism_engine'] as Map<String, dynamic>;
      expect(realism['intimate_preferences'], {
        'into': ['slow mornings'],
        'not_into': ['an audience'],
      });
      // ...and is NOT smuggled into the everyday lists.
      expect(realism['likes'], isNot(contains('slow mornings')));
    });

    test('a card with no preferences at all reads as empty, not null', () {
      final back = FrontPorchExtensions.fromJson(const {'realism_engine': {}});
      expect(back.likes, isEmpty);
      expect(back.dislikes, isEmpty);
      expect(back.intimateInto, isEmpty);
      expect(back.intimateNotInto, isEmpty);
    });

    test('blank and non-string entries are dropped, not carried', () {
      final back = FrontPorchExtensions.fromJson(const {
        'realism_engine': {
          'likes': ['  thunderstorms  ', '', '   ', 42, null, true],
        },
      });
      expect(back.likes, ['thunderstorms']);
    });

    test('a malformed list never throws — the whole import must not fail', () {
      for (final junk in <Object>[
        'being read to', // a bare string where a list belongs
        7,
        {'a': 1},
      ]) {
        expect(
          () => FrontPorchExtensions.fromJson({
            'realism_engine': {'likes': junk, 'dislikes': junk},
          }),
          returnsNormally,
          reason: 'junk: $junk',
        );
      }
    });

    test('a malformed intimate_preferences object never throws', () {
      for (final junk in <Object>['nope', 3, <String>[]]) {
        final back = FrontPorchExtensions.fromJson({
          'realism_engine': {'intimate_preferences': junk},
        });
        expect(back.intimateInto, isEmpty, reason: 'junk: $junk');
        expect(back.intimateNotInto, isEmpty);
      }
    });
  });

  group('the web bridge', () {
    test('all four lists survive extensions -> json -> extensions', () {
      final back = frontPorchFromFields(frontPorchToJson(seeded()));
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.dislikes, ['being interrupted']);
      expect(back.intimateInto, ['slow mornings']);
      expect(back.intimateNotInto, ['an audience']);
      expect(back.planLines, ['finish the log before the tide']);
    });

    test('an older web client that omits the keys keeps the base values', () {
      // The exact shape of the ambitions bug: a payload without the key must
      // fall back to what the card already had, NOT wipe it.
      final back = frontPorchFromFields(const {}, base: seeded());
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.intimateInto, ['slow mornings']);
      expect(back.planLines, ['finish the log before the tide']);
    });

    test('a client sending junk falls back rather than throwing', () {
      final back = frontPorchFromFields(const {
        'likes': 'being read to',
        'intimateInto': 5,
      }, base: seeded());
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.intimateInto, ['slow mornings']);
    });
  });
}
