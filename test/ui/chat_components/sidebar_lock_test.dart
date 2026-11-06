// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The sidebar layout lock: toggled on, every grip is inert and a drag moves
// nothing; Reset to default still restores the shipped order while locked
// (and does not silently unlock); toggled off, dragging returns. Desktop twin
// of web_ui/src/components/SidebarLock.reorder.test.tsx.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_body.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import '../pages/home/home_page_harness.dart';

/// Opens the seeded 1:1 chat and lets the sidebar paint. Session load runs on
/// the real event loop (the rig's Drift isolate), so wait it out for real.
Future<StorageService> _openChat(WidgetTester tester, HomeRig rig) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await rig.pump(tester);
  await tester.tap(find.text('Ada').first);
  await tester.pump();
  for (var i = 0; i < 300 && rig.chat.isLoadingSession; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(ChatPage), findsOneWidget);
  return rig.storage;
}

/// Y coordinates of each rendered section item, top-first.
List<String> _screenOrder(WidgetTester tester, List<String> ids) {
  final withY = [
    for (final id in ids)
      if (find
              .byKey(ValueKey('sidebar-section-$id'))
              .evaluate()
              .isNotEmpty)
        (id, tester.getTopLeft(find.byKey(ValueKey('sidebar-section-$id'))).dy),
  ];
  withY.sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (id, _) in withY) id];
}

void main() {
  testWidgets('the lock stops drags, Reset still works while locked, and '
      'unlocking restores dragging', (tester) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    final storage = await _openChat(tester, rig);
    final ui = storage.uiSettings;

    // Move a section first, so Reset has an arrangement to undo.
    final grip = find
        .descendant(
          of: find.byKey(const ValueKey('sidebar-section-one_shot_eval')),
          matching: find.byIcon(Icons.drag_handle),
        )
        .first;
    final gripCenter = tester.getCenter(grip);
    final pillTop = tester.getTopLeft(
      find.byKey(const ValueKey('sidebar-section-tool_calling_pill')),
    );
    final pillHeight = tester
        .getSize(find.byKey(const ValueKey('sidebar-section-tool_calling_pill')))
        .height;
    await tester.timedDrag(
      grip,
      Offset(0, pillTop.dy + pillHeight / 2 - gripCenter.dy),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
    expect(
      _screenOrder(tester, ['one_shot_eval', 'tool_calling_pill']),
      ['tool_calling_pill', 'one_shot_eval'],
    );

    // Lock: the pill flips, the grips become inert lock icons.
    await tester.tap(find.text('Lock layout'));
    await tester.pumpAndSettle();
    expect(ui.sidebarLayoutLocked, isTrue);
    expect(find.text('Layout locked'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SidebarBody),
        matching: find.byIcon(Icons.drag_handle),
      ),
      findsNothing,
      reason: 'no grip in the body can start a drag while locked',
    );
    expect(
      find.descendant(
        of: find.byType(SidebarBody),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsWidgets,
      reason: 'every grip draws the locked state',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sidebar_layout_locked'), isTrue);

    // A drag on the inert grip moves nothing.
    final lockIcon = find
        .descendant(
          of: find.byKey(const ValueKey('sidebar-section-one_shot_eval')),
          matching: find.byIcon(Icons.lock_outline),
        )
        .first;
    await tester.drag(
      lockIcon,
      Offset(
        0,
        tester.getTopLeft(
                  find.byKey(const ValueKey('sidebar-section-tool_calling_pill')),
                ).dy +
            pillHeight / 2 -
            tester.getCenter(lockIcon).dy,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _screenOrder(tester, ['one_shot_eval', 'tool_calling_pill']),
      ['tool_calling_pill', 'one_shot_eval'],
      reason: 'a locked sidebar cannot be reordered',
    );

    // Reset to default still works while locked — and does not unlock.
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(find.text('Reset sidebar to default?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(ui.sidebarOrder.first, 'director');
    expect(
      _screenOrder(tester, ['one_shot_eval', 'tool_calling_pill']),
      ['one_shot_eval', 'tool_calling_pill'],
      reason: 'Reset restores the shipped order even while locked',
    );
    expect(
      ui.sidebarLayoutLocked,
      isTrue,
      reason: 'resetting the order must not silently re-open the lock',
    );
    expect(find.text('Layout locked'), findsOneWidget);

    // Unlock: dragging is back.
    await tester.tap(find.text('Layout locked'));
    await tester.pumpAndSettle();
    expect(ui.sidebarLayoutLocked, isFalse);
    expect(prefs.getBool('sidebar_layout_locked'), isNull);
    expect(
      find.descendant(
        of: find.byType(SidebarBody),
        matching: find.byIcon(Icons.drag_handle),
      ),
      findsWidgets,
    );
  });
}
