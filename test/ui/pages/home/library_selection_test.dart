// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The home page's picks now live in LibrarySelection. These pin the rules
// it took over from HomePage unchanged (taking the last pick out ends the
// mode; Select none stays; Select all starts Multi-select; the ✕ clears
// everything) and the Shift range's edge cases.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/library_selection.dart';

void main() {
  test('a click toggles one card; the last pick out ends the mode', () {
    final sel = LibrarySelection()..toggleSelectMode();
    sel.toggle('Ann', group: false);
    sel.toggle('crew', group: true);
    expect(sel.characterIds, {'Ann'});
    expect(sel.groupIds, {'crew'});
    sel.toggle('Ann', group: false);
    expect(sel.isSelecting, isTrue, reason: 'Crew is still picked');
    sel.toggle('crew', group: true);
    expect(sel.picking, isFalse);
  });

  test('Select none stays picking; the ✕ clears and leaves', () {
    final sel = LibrarySelection()..toggleOrganizeMode();
    sel.selectAll({'Ann', 'Bo'}, {'crew'});
    expect(sel.isOrganizing, isTrue, reason: 'Select all keeps the mode');
    sel.selectNone();
    expect(sel.isEmpty, isTrue);
    expect(sel.isOrganizing, isTrue);
    sel.selectAll({'Ann'}, const {});
    sel.cancel();
    expect(sel.isEmpty, isTrue);
    expect(sel.picking, isFalse);
  });

  test('Select all outside a mode starts Multi-select; nothing to add, '
      'nothing happens', () {
    final sel = LibrarySelection();
    sel.selectAll(const {}, const {});
    expect(sel.picking, isFalse);
    sel.selectAll({'Ann'}, const {});
    expect(sel.isSelecting, isTrue);
  });

  test('a Shift range runs both ways and falls back to a toggle', () {
    const order = ['crew', 'Ann', 'Bo', 'Cy', 'Dee'];
    const groupKeys = {'crew'};
    final sel = LibrarySelection();
    // No anchor yet: a plain toggle, which becomes the anchor.
    sel.addRange('Cy', group: false, order: order, groupKeys: groupKeys);
    expect(sel.characterIds, {'Cy'});
    sel.addRange('crew', group: true, order: order, groupKeys: groupKeys);
    expect(sel.groupIds, {'crew'});
    expect(sel.characterIds, {'Ann', 'Bo', 'Cy'});
    // An anchor hidden by a search is not in [order]: a plain toggle.
    sel.toggle('Zed', group: false);
    sel.addRange('Dee', group: false, order: order, groupKeys: groupKeys);
    expect(sel.characterIds, {'Ann', 'Bo', 'Cy', 'Zed', 'Dee'});
  });

  test('a box replaces the picks and starts the mode once it touches one', () {
    final sel = LibrarySelection();
    sel.replace(const {}, const {});
    expect(sel.picking, isFalse, reason: 'an empty box starts nothing');
    sel.replace({'Ann'}, {'crew'});
    expect(sel.isSelecting, isTrue);
    sel.replace({'Bo'}, const {});
    expect(sel.characterIds, {'Bo'});
    expect(sel.groupIds, isEmpty);
  });
}
