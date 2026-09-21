// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Enhance Review says "New lorebook entries" — Save must append those
// onto the book duplicateCharacter just copied, never replace it.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

void main() {
  test('mergeLorebookEntries appends and replaces by name', () {
    final original = [
      LorebookEntry(name: 'The Kitchen', content: 'original kitchen'),
      LorebookEntry(name: 'The Porch', content: 'original porch'),
    ];
    final incoming = [
      LorebookEntry(name: 'The Bar', content: 'new bar'),
      LorebookEntry(name: 'The Kitchen', content: 'rewritten kitchen'),
    ];
    final merged = mergeLorebookEntries(original, incoming);
    expect(merged.map((e) => e.name), ['The Kitchen', 'The Porch', 'The Bar']);
    expect(merged[0].content, 'rewritten kitchen');
    expect(merged[1].content, 'original porch');
    expect(merged[2].content, 'new bar');
  });
}
