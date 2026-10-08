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

  test(
    'a Shift range runs both ways; with no anchor it picks only its card',
    () {
      const order = ['crew', 'Ann', 'Bo', 'Cy', 'Dee'];
      const groupKeys = {'crew'};
      final sel = LibrarySelection();
      // No anchor yet: only Cy is picked, and it becomes the anchor.
      sel.addRange('Cy', group: false, order: order, groupKeys: groupKeys);
      expect(sel.characterIds, {'Cy'});
      sel.addRange('crew', group: true, order: order, groupKeys: groupKeys);
      expect(sel.groupIds, {'crew'});
      expect(sel.characterIds, {'Ann', 'Bo', 'Cy'});
      // An anchor hidden by a search is not in [order]: only Dee is picked.
      sel.toggle('Zed', group: false);
      sel.addRange('Dee', group: false, order: order, groupKeys: groupKeys);
      expect(sel.characterIds, {'Ann', 'Bo', 'Cy', 'Zed', 'Dee'});
      // Picking, never unpicking: an anchorless Shift-click on a pick keeps it.
      sel.selectNone();
      sel.selectAll({'Bo'}, const {});
      sel.addRange('Bo', group: false, order: order, groupKeys: groupKeys);
      expect(sel.characterIds, {'Bo'});
    },
  );

  test('leaving a mode by its toolbar toggle drops the Shift anchor', () {
    const order = ['Ann', 'Bo', 'Cy', 'Dee', 'Eve'];
    final sel = LibrarySelection()..toggle('Ann', group: false);
    sel.toggleSelectMode(); // the toolbar's Multi-select, pressed again
    expect(sel.characterIds, isEmpty);
    sel.addRange('Eve', group: false, order: order, groupKeys: const {});
    expect(sel.characterIds, {'Eve'}, reason: 'no range from the old Ann');
  });

  test('a box and Select none move or drop the Shift anchor', () {
    const order = ['crew', 'Ann', 'Bo', 'Cy', 'Dee', 'Eve'];
    const groupKeys = {'crew'};
    final sel = LibrarySelection()..toggle('Eve', group: false);
    sel.replace({'Ann', 'Bo'}, const {}, 'Bo');
    sel.addRange('crew', group: true, order: order, groupKeys: groupKeys);
    expect(sel.characterIds, {'Ann', 'Bo'}, reason: 'from Bo, not from Eve');
    expect(sel.groupIds, {'crew'});

    sel.selectNone();
    sel.addRange('Dee', group: false, order: order, groupKeys: groupKeys);
    expect(sel.characterIds, {'Dee'});

    // A box that touched nothing leaves no anchor either.
    sel.replace(const {}, const {});
    sel.addRange('Ann', group: false, order: order, groupKeys: groupKeys);
    expect(sel.characterIds, {'Ann'});
  });

  test('Esc calls off a drag in flight and keeps the picks; a second Esc '
      'ends the selection', () {
    final sel = LibrarySelection()..replace({'Ann', 'Bo'}, const {});
    sel.beginDrag(2, picks: true);
    expect(sel.dragCount, 2);
    expect(sel.dragsPicks, isTrue);

    sel.escape();
    expect(sel.dragCalledOff, isTrue);
    expect(sel.dragCount, 0, reason: 'the toolbar leaves the drag row');
    expect(sel.dragsPicks, isFalse, reason: 'the picks stop being dimmed');
    expect(sel.characterIds, {'Ann', 'Bo'});
    expect(sel.isSelecting, isTrue);

    sel.endDrag();
    expect(sel.dragCalledOff, isFalse, reason: 'the next drag starts afresh');
    sel.escape();
    expect(sel.picking, isFalse);
    expect(sel.isEmpty, isTrue);
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
