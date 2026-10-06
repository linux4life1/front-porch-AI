// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library phase 2, selection gestures, on the real grid:
//   - a quick mouse drag draws a terracotta box and picks every character
//     and group card it touches (folder tiles never), starting the
//     selection by itself; a new box replaces the picks, a box with Ctrl
//     held adds to them;
//   - Shift-click picks the range from the last clicked card, in grid order;
//   - Ctrl/Cmd-click toggles one card, even before a selection exists, and
//     does not open it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';

import 'library_gesture_harness.dart';

void main() {
  late GestureLibrary lib;

  setUp(() async {
    lib = await GestureLibrary.create(
      ['Ann', 'Bo', 'Cy', 'Dee', 'Eve'],
      groups: [GroupChat(id: 'group_crew', name: 'Crew')],
    );
    await lib.folders.createFolder('Attic');
    await lib.folders.reload();
  });

  tearDown(() => lib.dispose());

  /// A quick mouse drag from the centre of [from] to the centre of [to].
  Future<void> boxDrag(WidgetTester tester, String from, String to) async {
    final start = centerOf(tester, from);
    final end = centerOf(tester, to);
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    for (var i = 1; i <= 4; i++) {
      await mouse.moveTo(Offset.lerp(start, end, i / 4)!);
      await tester.pump();
    }
    expect(find.byKey(const Key('library-select-box')), findsOneWidget);
    await mouse.up();
    await tester.pump();
    expect(find.byKey(const Key('library-select-box')), findsNothing);
  }

  testWidgets('a box picks what it touches — never the folder — and a new '
      'box replaces the picks unless Ctrl is held', (tester) async {
    await lib.pump(tester);
    final sel = lib.selection;
    expect(sel.picking, isFalse);

    // Grid order: Attic (folder), Crew (group), Ann, Bo, Cy, Dee, Eve.
    await boxDrag(tester, 'Attic', 'Bo');
    expect(sel.isSelecting, isTrue, reason: 'a box starts the selection');
    expect(sel.characterIds, {'Ann', 'Bo'});
    expect(sel.groupIds, {'group_crew'});
    expect(lib.opened, isEmpty, reason: 'a box is not a click');

    await boxDrag(tester, 'Dee', 'Eve');
    expect(sel.characterIds, {'Dee', 'Eve'}, reason: 'a plain box replaces');
    expect(sel.groupIds, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await boxDrag(tester, 'Ann', 'Bo');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sel.characterIds, {'Ann', 'Bo', 'Dee', 'Eve'});
  });

  testWidgets('Shift-click adds the range from the last clicked card', (
    tester,
  ) async {
    await lib.pump(tester);
    final sel = lib.selection;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Ann'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(sel.characterIds, {'Ann'});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Dee'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sel.characterIds, {'Ann', 'Bo', 'Cy', 'Dee'});

    // Backwards across a group chat, from a new anchor.
    await tester.tap(find.text('Eve'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Crew'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sel.groupIds, {'group_crew'});
    expect(sel.characterIds, {'Ann', 'Bo', 'Cy', 'Dee', 'Eve'});
    expect(lib.opened, isEmpty);
  });

  testWidgets('Ctrl/Cmd-click toggles one card without opening it', (
    tester,
  ) async {
    await lib.pump(tester);
    final sel = lib.selection;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Cy'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(sel.isSelecting, isTrue);
    expect(sel.characterIds, {'Cy'});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.text('Crew'), kind: PointerDeviceKind.mouse);
    await tester.tap(find.text('Cy'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(sel.characterIds, isEmpty);
    expect(sel.groupIds, {'group_crew'});
    expect(lib.opened, isEmpty, reason: 'a modified click never opens a chat');

    // A plain click outside a selection still opens the card.
    sel.cancel();
    await tester.pump();
    await tester.tap(find.text('Bo'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(lib.opened, ['Bo']);
  });

  testWidgets('a box moves the Shift anchor to its last card', (tester) async {
    await lib.pump(tester);
    final sel = lib.selection;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Eve'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await boxDrag(tester, 'Ann', 'Bo');
    expect(sel.characterIds, {'Ann', 'Bo'});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Crew'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    // From Bo back to Crew — not from Eve, which the box replaced.
    expect(sel.groupIds, {'group_crew'});
    expect(sel.characterIds, {'Ann', 'Bo'});
  });

  testWidgets('Select none forgets the anchor: Shift-click then picks only '
      'that card', (tester) async {
    await lib.pump(tester);
    final sel = lib.selection;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Ann'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Select none'));
    await tester.pump();
    expect(sel.isEmpty, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Cy'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sel.characterIds, {'Cy'});
  });

  /// A press at [at], moved by [by], let go: a slip, not a box.
  Future<void> slip(WidgetTester tester, Offset at, Offset by) async {
    final mouse = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await mouse.moveTo(at + by / 2);
    await tester.pump();
    await mouse.moveTo(at + by);
    await tester.pump();
    expect(find.byKey(const Key('library-select-box')), findsNothing);
    await mouse.up();
    await tester.pump();
  }

  testWidgets('a slip under 8 px changes nothing; on a card it is a click', (
    tester,
  ) async {
    await lib.pump(tester);
    final sel = lib.selection;
    sel.replace({'Ann', 'Bo'}, const {});
    await tester.pump();

    final below = tester.getBottomLeft(find.text('Ann')) + const Offset(0, 120);
    await slip(tester, below, const Offset(5, 4));
    expect(sel.characterIds, {'Ann', 'Bo'}, reason: 'a slip on empty space');

    await slip(tester, centerOf(tester, 'Cy'), const Offset(5, 4));
    expect(sel.characterIds, {
      'Ann',
      'Bo',
      'Cy',
    }, reason: 'a slip on a card is a click: it toggles that card');
  });

  testWidgets('a real box over empty space replaces the picks; with Ctrl it '
      'keeps them', (tester) async {
    await lib.pump(tester);
    final sel = lib.selection;
    sel.replace({'Ann', 'Bo'}, const {});
    await tester.pump();
    final below = tester.getBottomLeft(find.text('Ann')) + const Offset(0, 120);

    Future<void> emptyBox() async {
      final mouse = await tester.startGesture(
        below,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      for (var i = 1; i <= 4; i++) {
        await mouse.moveTo(below + Offset(15.0 * i, 15.0 * i));
        await tester.pump();
      }
      await mouse.up();
      await tester.pump();
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await emptyBox();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sel.characterIds, {'Ann', 'Bo'});

    await emptyBox();
    expect(sel.isEmpty, isTrue);
    expect(sel.isSelecting, isTrue, reason: 'still picking, with nothing');
  });
}
