// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Rewrite the lorebook" keeps what the user wrote. The generator's stamp
// must survive the database blob and the card file, an edited entry must
// read as hand-edited, and a merge must keep those entries in place.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

LorebookEntry _entry(String name, {bool constant = false}) => LorebookEntry(
  name: name,
  keys: [name.toLowerCase()],
  content: 'About $name.',
  constant: constant,
);

void main() {
  test('a stamped entry is the generator\'s until its text changes', () {
    final book = Lorebook(entries: [_entry('Tavern'), _entry('Harbour')]);
    expect(book.entries.every(isHandEdited), isTrue, reason: 'no stamp yet');

    stampLoreFingerprints(book);
    expect(book.entries.any(isHandEdited), isFalse);

    book.entries[1].content = 'The harbour, as I wrote it.';
    expect(isHandEdited(book.entries[1]), isTrue);
    book.entries[0].keys = ['inn'];
    expect(isHandEdited(book.entries[0]), isTrue);
  });

  test('the stamp survives the database blob and the card file', () {
    final book = Lorebook(entries: [_entry('Tavern'), _entry('Harbour')]);
    stampLoreFingerprints(book);

    final fromDb = Lorebook.fromJson(
      jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>,
    );
    expect(fromDb.entries.any(isHandEdited), isFalse);

    final card = CharacterCard(name: 'Mira', lorebook: book);
    final fromFile = V2CardService().parseCardJson(jsonEncode(card.toJson()));
    expect(fromFile!.lorebook!.entries, hasLength(2));
    expect(fromFile.lorebook!.entries.any(isHandEdited), isFalse);
  });

  test('a merge keeps hand-edited entries in place and the book settings', () {
    final current = Lorebook(
      entries: [
        _entry('Premise', constant: true),
        _entry('Tavern'),
        _entry('Harbour'),
      ],
      scanDepth: 7,
      tokenBudget: 900,
      recursiveScanning: false,
      extensions: {'note': 'kept'},
    );
    stampLoreFingerprints(current);
    current.entries[1].content = 'My tavern.';

    final generated = Lorebook(
      entries: [
        _entry('New premise', constant: true),
        _entry('Lighthouse'),
        _entry('Market'),
      ],
    );
    stampLoreFingerprints(generated);

    final merged = mergeRewrittenLorebook(
      current: current,
      generated: generated,
    );
    expect(merged.entries.map((e) => e.name), [
      'New premise',
      'Tavern',
      'Lighthouse',
      'Market',
    ]);
    expect(merged.entries[1].content, 'My tavern.');
    expect(isHandEdited(merged.entries[1]), isTrue);
    expect(merged.entries.where(isHandEdited), hasLength(1));
    expect(merged.scanDepth, 7);
    expect(merged.tokenBudget, 900);
    expect(merged.recursiveScanning, isFalse);
    expect(merged.extensions, {'note': 'kept'});
  });

  test('a kept entry wins over a new one of its name, and over a second '
      'always-on premise', () {
    final current = Lorebook(
      entries: [_entry('Premise', constant: true), _entry('Tavern')],
    );
    stampLoreFingerprints(current);
    current.entries[0].content = 'My world.';
    current.entries[1].content = 'My tavern.';

    final generated = Lorebook(
      entries: [
        _entry('Another premise', constant: true),
        _entry('tavern'),
        _entry('Docks'),
      ],
    );
    final merged = mergeRewrittenLorebook(
      current: current,
      generated: generated,
    );
    expect(merged.entries.map((e) => e.name), ['Premise', 'Tavern', 'Docks']);
    expect(merged.entries.where((e) => e.constant), hasLength(1));
  });
}
