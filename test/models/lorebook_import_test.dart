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

// The steps after a lorebook is decoded, and the two surfaces that take them.
//
// Decoding was always shared. Everything after it — deep-copying the book,
// picking a free world name, merging into a group's stored JSON — was written
// twice, once in the desktop wizard and once in the web relay. The aliasing
// case below is why the copy matters: hand out the parsed entries directly and
// editing the destination edits the file you imported.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';

Lorebook _book() => Lorebook(
  entries: [
    LorebookEntry(keys: ['porch'], content: 'A wide porch.'),
  ],
  scanDepth: 3,
  tokenBudget: 512,
  recursiveScanning: true,
  extensions: {'source': 'test'},
);

void main() {
  group('cloneLorebook', () {
    test('carries the book-level settings across', () {
      final copy = cloneLorebook(_book());
      expect(copy.scanDepth, 3);
      expect(copy.tokenBudget, 512);
      expect(copy.recursiveScanning, isTrue);
      expect(copy.extensions['source'], 'test');
      expect(copy.entries.single.content, 'A wide porch.');
    });

    test('the copy does not alias the source', () {
      final source = _book();
      final copy = cloneLorebook(source);
      copy.entries.single.content = 'Edited in the destination.';
      copy.extensions['source'] = 'edited';
      expect(
        source.entries.single.content,
        'A wide porch.',
        reason: 'editing an imported entry must not edit the parsed file',
      );
      expect(source.extensions['source'], 'test');
    });
  });

  group('appendToGroupLorebookJson', () {
    test('appends to an existing book', () {
      final existing = jsonEncode(_book().toJson());
      final merged = appendToGroupLorebookJson(existing, [
        LorebookEntry(keys: ['lamp'], content: 'One lamp, always lit.'),
      ]);
      final book = Lorebook.fromJson(
        jsonDecode(merged) as Map<String, dynamic>,
      );
      expect(book.entries.map((e) => e.content), [
        'A wide porch.',
        'One lamp, always lit.',
      ]);
    });

    test('an empty column starts a fresh book', () {
      final merged = appendToGroupLorebookJson('', [
        LorebookEntry(keys: ['lamp'], content: 'One lamp.'),
      ]);
      final book = Lorebook.fromJson(
        jsonDecode(merged) as Map<String, dynamic>,
      );
      expect(book.entries.single.content, 'One lamp.');
    });

    test('unreadable stored lore still accepts the import', () {
      final merged = appendToGroupLorebookJson('not json at all', [
        LorebookEntry(keys: ['lamp'], content: 'One lamp.'),
      ]);
      final book = Lorebook.fromJson(
        jsonDecode(merged) as Map<String, dynamic>,
      );
      expect(book.entries.single.content, 'One lamp.');
    });
  });

  test('both import surfaces take the shared steps', () {
    const surfaces = [
      'lib/ui/pages/import_lorebook_page.dart',
      'lib/services/web/facade/world_facade.import.dart',
    ];
    for (final path in surfaces) {
      final source = File(path).readAsStringSync();
      for (final fn in [
        'cloneLorebook',
        'uniqueWorldName',
        'appendToGroupLorebookJson',
      ]) {
        expect(
          source.contains(fn),
          isTrue,
          reason: '$path must import lorebooks through $fn',
        );
      }
      expect(
        source.contains('while (taken.contains('),
        isFalse,
        reason: '$path grew its own free-name loop again',
      );
    }
  });
}
