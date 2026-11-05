// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The reorderable chat sidebar: a grip drag moves a section, the order
// survives a remount through mocked prefs, Reset restores the shipped
// default, a section hidden right now keeps its stored slot, and the
// Character State accordion's portions move within it. The grip never
// steals the control it sits on (Error Book P44).

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/ui_settings.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_body.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar.dart';

import '../pages/home/home_page_harness.dart';
import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Opens the seeded 1:1 chat and lets the sidebar paint. Session load runs on
/// the real event loop (the rig's Drift isolate), so wait it out for real.
Future<StorageService> _openChat(WidgetTester tester, HomeRig rig) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await rig.pump(tester);
  await _enterChat(tester, rig);
  return rig.storage;
}

Future<void> _enterChat(WidgetTester tester, HomeRig rig) async {
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
  expect(find.byType(ChatRightSidebar), findsOneWidget);
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
  testWidgets('grip drag reorders a top-level section, the order survives '
      'a remount, and Reset restores the default', (tester) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    final storage = await _openChat(tester, rig);
    final ui = storage.uiSettings;

    // Pin the default: the one-shot row sits above the tool-calling pill.
    expect(
      _screenOrder(tester, ['one_shot_eval', 'tool_calling_pill']),
      ['one_shot_eval', 'tool_calling_pill'],
    );

    // P40 discipline: derive the drag from the product's midpoint rule.
    // Drop the grip past the pill item's middle so the trade is triggered.
    final grip = find
        .descendant(
          of: find.byKey(const ValueKey('sidebar-section-one_shot_eval')),
          matching: find.byIcon(Icons.drag_handle),
        )
        .first;
    final gripCenter = tester.getCenter(grip);
    final pillTop =
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-section-tool_calling_pill')));
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
      reason: 'the drag crossed the pill item midpoint and traded places',
    );
    // Stored order (merged): the hidden director and lite_banner keep slots
    // 0 and 3, the two visible ids traded 1↔2.
    final prefs = await SharedPreferences.getInstance();
    final stored =
        (jsonDecode(prefs.getString('sidebar_order')!) as List).cast<String>();
    expect(
      stored,
      [
        'director',
        'tool_calling_pill',
        'one_shot_eval',
        'lite_banner',
        'author_note',
        'wiki',
        'character_state',
        'journal_memory',
        'objectives',
        'story_tools',
      ],
    );

    // Remount: leave the chat and push it again; the painted order holds.
    Navigator.of(tester.element(find.byType(ChatPage))).pop();
    await tester.pumpAndSettle();
    await _enterChat(tester, rig);
    expect(
      _screenOrder(tester, ['one_shot_eval', 'tool_calling_pill']),
      ['tool_calling_pill', 'one_shot_eval'],
    );

    // The Reset pill is pinned chrome sitting under Main Settings — not
    // above the portrait, where the mood ring hid it — and it asks first:
    // the order is shared by all chats.
    final pill = find.text('Reset to default');
    expect(pill, findsOneWidget);
    expect(
      tester.getTopLeft(pill).dy,
      greaterThan(tester.getBottomLeft(find.text('Main Settings')).dy),
      reason: 'the pill sits under Main Settings, clear of the portrait',
    );
    expect(
      tester.getTopLeft(pill).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('sidebar-section-one_shot_eval')))
            .dy,
      ),
      reason: 'and above the reorderable body',
    );
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.text('Reset sidebar to default?'), findsOneWidget);

    // 'Keep mine' changes nothing.
    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();
    expect(ui.sidebarOrder[1], 'tool_calling_pill');
    expect(prefs.getString('sidebar_order'), isNotNull);

    // The confirm resets.
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(ui.sidebarOrder.first, 'director');
    expect(prefs.getString('sidebar_order'), isNull);
    expect(
      _screenOrder(tester, ['one_shot_eval', 'tool_calling_pill']),
      ['one_shot_eval', 'tool_calling_pill'],
    );
  });

  testWidgets('a section hidden right now keeps its stored slot', (_) async {
    final ui = UiSettings();
    // Reorder while Objectives and Journal are hidden (inactive 1:1): the
    // visible ids move, the hidden ids are not in the list at all. Story
    // Tools jumps to the front of what shows.
    await ui.setSidebarOrder([
      'story_tools',
      'one_shot_eval',
      'tool_calling_pill',
      'wiki',
    ]);
    // When the hidden ones reappear they land back in their stored slots
    // (Objectives between Journal and Story Tools' old place), and nothing
    // is dropped or re-sorted.
    final back = ui.sidebarOrderFor([
      'one_shot_eval',
      'tool_calling_pill',
      'wiki',
      'story_tools',
      'objectives',
      'journal_memory',
    ]);
    expect(
      back,
      [
        'story_tools',
        'one_shot_eval',
        'tool_calling_pill',
        'journal_memory',
        'objectives',
        'wiki',
      ],
    );
  });

  testWidgets('Character State portions carry grips and reorder inside the '
      'accordion', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);

    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: CharacterStateGroup(
                  chat: chat,
                  isGroup: false,
                  initiallyExpanded: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every portion this 1:1 chat shows carries its own grip.
    final portionIds = ['bond_bars', 'needs', 'time'];
    for (final id in portionIds) {
      expect(
        find.byKey(ValueKey('sidebar-leaf-$id')),
        findsOneWidget,
        reason: 'the $id portion renders',
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('sidebar-leaf-$id')),
          matching: find.byIcon(Icons.drag_handle),
        ),
        findsOneWidget,
        reason: 'the $id portion carries a grip',
      );
    }

    // Drag the needs grip past the bars' midpoint: needs moves first.
    final grip = find
        .descendant(
          of: find.byKey(const ValueKey('sidebar-leaf-needs')),
          matching: find.byIcon(Icons.drag_handle),
        )
        .first;
    final gripCenter = tester.getCenter(grip);
    final barsTop =
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-leaf-bond_bars')));
    final barsHeight =
        tester.getSize(find.byKey(const ValueKey('sidebar-leaf-bond_bars'))).height;
    await tester.drag(
      grip,
      Offset(0, barsTop.dy + barsHeight / 2 - gripCenter.dy),
    );
    await tester.pumpAndSettle();

    expect(
      storage.uiSettings.sidebarLeafOrderFor(
        'character_state',
        ['bond_bars', 'needs', 'time'],
      ),
      ['needs', 'bond_bars', 'time'],
    );
    final needsY =
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-leaf-needs'))).dy;
    final barsY = tester
        .getTopLeft(find.byKey(const ValueKey('sidebar-leaf-bond_bars')))
        .dy;
    expect(needsY, lessThan(barsY));
  });

  testWidgets('the grip never acts on the control it sits on (P44)', (
    tester,
  ) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    final expanded = <bool>[];

    Future<void> pump() => tester.pumpWidget(
          ChangeNotifierProvider<StorageService>.value(
            value: storage,
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  child: SingleChildScrollView(
                    child: CharacterStateGroup(
                      chat: chat,
                      isGroup: false,
                      initiallyExpanded: true,
                      onExpansionChanged: expanded.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump();
    await tester.pumpAndSettle();

    // A plain tap on a portion's grip toggles nothing.
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('sidebar-leaf-time')),
            matching: find.byIcon(Icons.drag_handle),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(expanded, isEmpty);

    // The header still toggles as it always did.
    await tester.tap(find.text('Character State'));
    await tester.pumpAndSettle();
    expect(expanded, [false]);
  });

  testWidgets('the wheel scrolls the sidebar while a tab is picked up', (
    tester,
  ) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    await _openChat(tester, rig);
    // A short window so the body actually scrolls.
    await tester.binding.setSurfaceSize(const Size(1440, 620));
    await tester.pumpAndSettle();

    // Pick up the first grip the body built (in a short window lower
    // sections are not built at all) and hold.
    final gripFinder = find
        .descendant(
          of: find.byType(SidebarBody),
          matching: find.byIcon(Icons.drag_handle),
        )
        .first;
    final sectionEl = tester.element(
      find.ancestor(of: gripFinder, matching: find.byType(KeyedSubtree)).first,
    );
    double bodyOffset() => Scrollable.of(sectionEl).position.pixels;

    final gripAt = tester.getCenter(gripFinder);
    final gesture = await tester.startGesture(gripAt);
    await gesture.moveBy(const Offset(0, 14));
    await tester.pump();

    final before = bodyOffset();
    // Mouse wheel while held: the pump scrolls the frozen list by hand.
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: gripAt,
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pump();
    expect(
      bodyOffset(),
      greaterThan(before),
      reason: 'the wheel moves the body while the tab is in hand',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
