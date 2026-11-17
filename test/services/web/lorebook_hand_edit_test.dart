// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's per-entry edit must register as hand-edited, so a later
// "Rewrite the lorebook" keeps it (desktop `isHandEdited` + merge). The web
// sends the entry's whole stored JSON back as `ext`; changing its text makes
// the stored generator fingerprint stop matching, which is exactly the
// desktop's test. This pins that round-trip through the web save path.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/lore_fingerprint.dart';
import 'package:front_porch_ai/services/web/facade/character/character_card_edits.dart';

LorebookEntry generatedEntry({String content = 'A wet rock.'}) {
  final entry = LorebookEntry()
    ..name = 'The Rock'
    ..keys = ['rock']
    ..content = content;
  stampLoreFingerprints(Lorebook(entries: [entry]));
  return entry;
}

Map<String, dynamic> rowFor(LorebookEntry entry, {required String content}) => {
  'name': entry.name,
  'key': entry.keys.join(', '),
  'content': content,
  'ext': entry.toJson(),
};

void main() {
  test('a web entry edit reads as hand-edited, so a rewrite keeps it', () {
    final entry = generatedEntry();
    final card = CharacterCard(name: 'Wren');
    applyCharacterFields(card, {
      'lorebook': [rowFor(entry, content: 'The rock I wrote by hand.')],
    }, needsSimDefault: false);
    final saved = card.lorebook!.entries.single;
    expect(saved.content, 'The rock I wrote by hand.');
    expect(saved.extensions[kLoreGeneratedKey], isNotNull);
    expect(isHandEdited(saved), isTrue);
  });

  test('an untouched generated entry stays the generator\'s', () {
    final entry = generatedEntry();
    final card = CharacterCard(name: 'Wren');
    applyCharacterFields(card, {
      'lorebook': [rowFor(entry, content: 'A wet rock.')],
    }, needsSimDefault: false);
    expect(isHandEdited(card.lorebook!.entries.single), isFalse);
  });
}
