// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Desktop cast chips: Promote stays the guest's only Promote chrome (the
// GUEST label is gone — the wider chip with a Promote button is already the
// guest's sign). The Next pill queues any member; a queued chip reads the
// other way and cancels. Proven red: drop the pill wiring and these fail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  test('Character State stays up for a group guest, not a 1:1 guest', () {
    expect(characterStateAccordionVisible(isLite: true, isGroup: true), isTrue);
    expect(
      characterStateAccordionVisible(isLite: true, isGroup: false),
      isFalse,
    );
    expect(
      characterStateAccordionVisible(isLite: false, isGroup: true),
      isTrue,
    );
    expect(
      characterStateAccordionVisible(isLite: false, isGroup: false),
      isTrue,
    );
  });

  testWidgets('lite chip shows a tappable Promote and no GUEST label', (
    t,
  ) async {
    var promoted = false;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: CastRosterChip(
            name: 'Mara',
            color: AppColors.formMasterAccent,
            isFocused: true,
            isLite: true,
            onFocus: () {},
            onPromote: () => promoted = true,
            onQueue: () {},
          ),
        ),
      ),
    );

    expect(find.text('GUEST'), findsNothing);
    expect(find.text('Promote'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Mara'), findsOneWidget);

    // The Next pill is the bottom row on every chip: a guest's Promote
    // rides above it, so the hold never moves between faces.
    expect(
      t.getTopLeft(find.text('Next')).dy,
      greaterThan(t.getTopLeft(find.text('Promote')).dy),
    );

    await t.tap(find.text('Promote'));
    expect(promoted, isTrue);
  });

  testWidgets('queued chip reads NEXT and its tap cancels', (t) async {
    var cancelled = false;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: CastRosterChip(
            name: 'Zinna',
            color: AppColors.formMasterAccent,
            isFocused: false,
            isLite: false,
            onFocus: () {},
            onQueue: () => cancelled = true,
            queued: true,
          ),
        ),
      ),
    );

    expect(find.text('NEXT'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    await t.tap(find.text('NEXT'));
    expect(cancelled, isTrue);
  });

  testWidgets('no queue wiring draws no pill (1:1 guest)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CastRosterChip(
            name: 'Zinna',
            color: AppColors.formMasterAccent,
            isFocused: false,
            isLite: false,
            onFocus: () {},
          ),
        ),
      ),
    );

    expect(find.text('Next'), findsNothing);
    expect(find.text('Promote'), findsNothing);
    expect(find.text('Zinna'), findsOneWidget);
  });
}
