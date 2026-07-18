// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

void main() {
  group('web lorebook bridge ext passthrough', () {
    test('advanced fields survive a web edit round-trip', () {
      final book = Lorebook(entries: [
        LorebookEntry.fromJson({
          'keys': ['queen'],
          'keysecondary': ['court'],
          'content': 'Original',
          'probability': 25,
          'order': 250,
          'position': 4,
          'selectiveLogic': 3,
          'extensions': {'chub_thing': true},
        }),
      ]);

      // Server → web rows (the web UI edits only the six simple fields)…
      final rows = lorebookEntriesToJson(book);
      expect(rows.single['ext'], isA<Map<String, dynamic>>());
      rows.single['content'] = 'Edited in browser';

      // …and web rows → server model.
      final rebuilt = buildLorebookFromJson(rows)!;
      final e = rebuilt.entries.single;
      expect(e.content, 'Edited in browser');
      expect(e.secondaryKeys, ['court']);
      expect(e.probability, 25);
      expect(e.order, 250);
      expect(e.position, 4);
      expect(e.selectiveLogic, SelectiveLogic.andAll);
      expect(e.extensions['chub_thing'], true);
    });

    test('probability + position ride the row additively', () {
      final book = Lorebook(entries: [
        LorebookEntry.fromJson({
          'keys': ['queen'],
          'content': 'x',
          'probability': 40,
          'position': 4,
        }),
      ]);
      final rows = lorebookEntriesToJson(book);
      expect(rows.single['probability'], 40);
      expect(rows.single['position'], 4);

      rows.single['probability'] = 65;
      rows.single['position'] = 2;
      final rebuilt = buildLorebookFromJson(rows)!.entries.single;
      expect(rebuilt.probability, 65);
      expect(rebuilt.position, 2);
    });

    test('rows omitting the new keys leave ext-decoded values untouched', () {
      final book = Lorebook(entries: [
        LorebookEntry.fromJson({
          'keys': ['queen'],
          'content': 'x',
          'probability': 40,
          'position': 4,
        }),
      ]);
      final rows = lorebookEntriesToJson(book)
          .map((r) => Map<String, dynamic>.from(r)
            ..remove('probability')
            ..remove('position'))
          .toList();
      final rebuilt = buildLorebookFromJson(rows)!.entries.single;
      expect(rebuilt.probability, 40); // from ext
      expect(rebuilt.position, 4);
    });

    test('rows without ext still build (fresh web-authored entries)', () {
      final rebuilt = buildLorebookFromJson([
        {
          'name': 'New',
          'key': 'vale, peaks',
          'content': 'Fresh',
          'enabled': true,
          'constant': false,
          'stickyDepth': 2,
        },
      ])!;
      final e = rebuilt.entries.single;
      expect(e.keys, ['vale', 'peaks']);
      expect(e.stickyDepth, 2);
      expect(e.order, 100); // clean defaults
    });
  });
}
