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

// Release-audit L1: deep @depth lore must not land at the HEAD of the
// included history window. High-depth keyword entries used to splice at
// lines.length (the start), so flipping one on/off rewrote the history
// string's first bytes and forced local prefix caches to re-prefill the
// whole transcript — undoing sticky trim + the monotonic anchor.
//
// Guard proven to fail before passing: drop the kDepthLoreMaxFromEnd
// clamp and the "depth 99" case inserts at index 0 of the output.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('depth 0 sits after the last message', () {
    final out = spliceDepthLore(
      ['A', 'B', 'C'],
      [const LoreDepthEntry(depth: 0, content: 'LORE')],
    );
    expect(out, ['A', 'B', 'C', 'LORE']);
  });

  test('depth 1 sits one message up from the end', () {
    final out = spliceDepthLore(
      ['A', 'B', 'C'],
      [const LoreDepthEntry(depth: 1, content: 'LORE')],
    );
    expect(out, ['A', 'B', 'LORE', 'C']);
  });

  test('depth beyond the max-from-end clamp stays in the recent tail', () {
    final lines = List.generate(20, (i) => 'm$i');
    final out = spliceDepthLore(
      lines,
      [const LoreDepthEntry(depth: 99, content: 'DEEP')],
    );
    // Must NOT be first — that was the cache-thrash bug.
    expect(out.first, isNot('DEEP'), reason: 'deep lore must not lead history');
    expect(out.first, 'm0');
    // Clamped to kDepthLoreMaxFromEnd from the end of the message list.
    final expectedIndex = lines.length - kDepthLoreMaxFromEnd;
    expect(out[expectedIndex], 'DEEP');
    expect(out[expectedIndex + 1], 'm$expectedIndex');
  });

  test('toggling deep lore never rewrites the sticky head of a long window', () {
    final lines = List.generate(24, (i) => 'turn-$i');
    final without = spliceDepthLore(lines, const []).join('\n');
    final withDeep = spliceDepthLore(
      lines,
      [const LoreDepthEntry(depth: 50, content: 'KEYWORD LORE')],
    ).join('\n');
    // Shared prefix must cover the entire sticky head (everything before
    // the clamp zone). Pre-fix, depth 50 put lore first and shared
    // prefix collapsed to zero.
    final n = without.length < withDeep.length ? without.length : withDeep.length;
    var shared = 0;
    while (shared < n &&
        without.codeUnitAt(shared) == withDeep.codeUnitAt(shared)) {
      shared++;
    }
    expect(
      shared,
      greaterThan(without.length * 5 ~/ 10),
      reason:
          'deep lore must only touch the recent tail so the sticky prefix '
          'stays byte-identical (shared $shared of ${without.length})',
    );
  });

  test('the latest-beat cut keeps every entry where it sat against the '
      'messages', () {
    const lore = [
      LoreDepthEntry(depth: 0, content: 'AFTER-LAST'),
      LoreDepthEntry(depth: 1, content: 'BEFORE-LAST'),
      LoreDepthEntry(depth: 3, content: 'DEEPER'),
    ];
    final lines = ['A', 'B', 'C', 'D'];
    final whole = spliceDepthLore(lines, lore);
    final cut = spliceDepthLoreSplit(lines, lore, tailCount: 1);
    // Rejoined, the cut is the plain splice: nothing moved or doubled.
    expect([...cut.body, ...cut.tail], whole);
    // Depth 0 rides with the newest line; depth 1 (exactly the cut) stays
    // at the end of the body, right where the moved line used to start.
    expect(cut.tail, ['D', 'AFTER-LAST']);
    expect(cut.body, ['A', 'DEEPER', 'B', 'C', 'BEFORE-LAST']);
    // No cut is the old splice.
    expect(spliceDepthLoreSplit(lines, lore, tailCount: 0).tail, isEmpty);
    // A cut wider than the window takes the whole window.
    expect(spliceDepthLoreSplit(lines, const [], tailCount: 9).body, isEmpty);
  });
}
