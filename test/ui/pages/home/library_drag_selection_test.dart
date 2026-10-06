// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library phase 3, moving the selection, on the real grid:
//   - press-and-hold a PICKED card, then drag: the whole selection comes
//     along (stacked ghost with a count, picked cards dimmed to 40%), a
//     folder tile says "Drop to move N here", and the drop is ONE moveMany
//     with every pick;
//   - while a drag is live every level of the path above is a drop target;
//   - holding an UNpicked card keeps today's one-card drag.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';

import 'library_gesture_harness.dart';

void main() {
  late GestureLibrary lib;

  setUp(() async {
    lib = await GestureLibrary.create(
      ['Ann', 'Bo', 'Cy'],
      groups: [GroupChat(id: 'group_crew', name: 'Crew')],
    );
  });

  tearDown(() => lib.dispose());

  /// Mouse press on [name], held past the drag delay.
  Future<TestGesture> hold(WidgetTester tester, String name) async {
    final mouse = await tester.startGesture(
      centerOf(tester, name),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    return mouse;
  }

  double opacityAbove(WidgetTester tester, String name) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(name).first, matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  testWidgets('holding a picked card drags every pick onto a folder tile, '
      'as one move', (tester) async {
    final attic = await lib.folders.createFolder('Attic');
    await lib.folders.reload();
    await lib.pump(tester);
    lib.selection.replace({'Ann', 'Bo'}, {'group_crew'});
    await tester.pump();

    final mouse = await hold(tester, 'Bo');
    expect(find.byKey(const Key('library-drag-ghost')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('library-drag-ghost')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(opacityAbove(tester, 'Ann'), 0.4, reason: 'picks dim while dragged');
    expect(opacityAbove(tester, 'Cy'), 1.0);
    expect(find.text('Drop on a folder'), findsOneWidget);

    await mouse.moveTo(centerOf(tester, 'Attic'));
    await tester.pump();
    expect(find.text('Drop to move 3 here'), findsOneWidget);

    await mouse.up();
    await tester.pumpAndSettle();
    expect(lib.folders.moves, hasLength(1), reason: 'one moveMany, not three');
    expect(lib.folders.moves.single.folderId, attic.id);
    expect(lib.folders.moves.single.files, {'Ann.png', 'Bo.png'});
    expect(lib.folders.moves.single.groups, {'group_crew'});
    expect(lib.folders.getCharactersInFolder(attic.id).toSet(), {
      'Ann.png',
      'Bo.png',
    });
    expect(lib.selection.picking, isFalse, reason: 'a move ends the picks');
    expect(find.byKey(const Key('library-drag-ghost')), findsNothing);
  });

  testWidgets('every level of the path takes the drop while a drag is live', (
    tester,
  ) async {
    final outer = await lib.folders.createFolder('Outer');
    final inner = await lib.folders.createFolder('Inner', parentId: outer.id);
    await lib.folders.moveMany(
      folderId: inner.id,
      characterPaths: ['/library/Ann.png', '/library/Bo.png'],
    );
    lib.folders.moves.clear();
    await lib.pump(tester, folderId: inner.id);
    lib.selection.replace({'Ann', 'Bo'}, const {});
    await tester.pump();

    final mouse = await hold(tester, 'Ann');
    expect(
      find.text('Drop on a folder, or on a level of the path'),
      findsOneWidget,
    );
    // Both levels above are targets; the folder you stand in is not.
    expect(find.text('My Characters'), findsOneWidget);
    expect(find.text('Outer'), findsOneWidget);

    await mouse.moveTo(tester.getCenter(find.text('My Characters')));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(lib.folders.moves, hasLength(1));
    expect(lib.folders.moves.single.folderId, isNull, reason: 'the top level');
    expect(lib.folders.moves.single.files, {'Ann.png', 'Bo.png'});
    expect(lib.folders.getCharactersInFolder(inner.id), isEmpty);
  });

  testWidgets('holding an unpicked card keeps the one-card drag', (
    tester,
  ) async {
    final attic = await lib.folders.createFolder('Attic');
    await lib.folders.reload();
    await lib.pump(tester);
    lib.selection.replace({'Ann'}, const {});
    await tester.pump();

    final mouse = await hold(tester, 'Cy');
    expect(find.byKey(const Key('library-drag-ghost')), findsNothing);
    expect(opacityAbove(tester, 'Ann'), 1.0, reason: 'picks stay as they are');
    await mouse.moveTo(centerOf(tester, 'Attic'));
    await tester.pump();
    expect(find.text('Drop to move 1 here'), findsOneWidget);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(lib.folders.moves.single.files, {'Cy.png'});
    expect(lib.selection.characterIds, {'Ann'}, reason: 'picks untouched');
    expect(lib.folders.getFolderForCharacter('/library/Cy.png')?.id, attic.id);
  });
}
