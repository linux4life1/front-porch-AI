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

// One reader for the receipt column, because three readers disagreed.
//
// Journal cards and Growth rings store receipts the same way, and three
// surfaces rendered them: the desktop diary, the desktop rings panel and the
// web relay. The desktop diary used `whereType<int>()`, so a position that had
// been through a JSON round-trip as 12.0 or "12" showed as a tappable pill in
// the browser and simply vanished in the app. Same card, same column, two
// answers.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/utils/utils.dart';

void main() {
  test('plain integers decode in order', () {
    expect(decodeReceiptIds('[3,9,12]'), [3, 9, 12]);
  });

  test('a position that round-tripped as a double still counts', () {
    expect(decodeReceiptIds('[12.0]'), [
      12,
    ], reason: 'the desktop diary used to drop these while the web kept them');
  });

  test('a position stored as a string still counts', () {
    expect(decodeReceiptIds('["12"]'), [12]);
  });

  test('nothing to read yields no receipts', () {
    expect(decodeReceiptIds(null), isEmpty);
    expect(decodeReceiptIds(''), isEmpty);
    expect(decodeReceiptIds('not json'), isEmpty);
    expect(decodeReceiptIds('{"a":1}'), isEmpty);
  });

  test('unreadable entries are skipped, not fatal', () {
    expect(decodeReceiptIds('[1,null,"x",4]'), [1, 4]);
  });

  test('every receipt surface reads the column through the shared decoder', () {
    const surfaces = [
      'lib/services/chat/growth_store.dart',
      'lib/services/web/facade/journal_web_surface.dart',
      'lib/ui/dialogs/journal_dialog.dart',
    ];
    for (final path in surfaces) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('decodeReceiptIds'),
        isTrue,
        reason: '$path must decode receipts through decodeReceiptIds',
      );
      expect(
        source.contains('whereType<int>()'),
        isFalse,
        reason: '$path grew its own receipt parser again',
      );
    }
  });
}
