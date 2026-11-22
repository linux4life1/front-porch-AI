// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Kit editor interaction coverage (docs/design/boons-and-bogies.md §4),
// same doctrine as wardrobe_editor_test.dart: a golden would show this
// section perfectly while its buttons do nothing. What gets pinned here is
// the contract the seeded ring inherits: kind decides the pin default, the
// tier travels, the 6-entry cap stops Add, and past three bogies the row
// says so before review says so louder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<TraitKitEntry>? last;
  var host = <TraitKitEntry>[];

  Future<void> pump(
    WidgetTester tester, {
    List<TraitKitEntry> values = const [],
  }) {
    host = [...values];
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              // The real callers hold the list and echo it back; without a
              // host the rows never re-render and tap-targets vanish.
              builder: (context, setState) => TraitKitEditor(
                values: host,
                onChanged: (v) {
                  last = v;
                  setState(() => host = v);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() => last = null);

  testWidgets('Add appends an unpinned empty boon and the counter is honest', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('0 of 6'), findsOneWidget);
    await tester.tap(find.text('Add trait'));
    await tester.pump();
    expect(last, hasLength(1));
    expect(last!.single.kind, 'boon');
    expect(last!.single.text, isEmpty);
    expect(last!.single.pinned, isFalse);
  });

  testWidgets('a card-authored entry shows its text in the field', (
    tester,
  ) async {
    await pump(
      tester,
      values: [
        TraitKitEntry(kind: 'bogey', text: 'bad temper', tier: 'established'),
      ],
    );
    expect(find.text('bad temper'), findsOneWidget);
    expect(find.text('1 of 6'), findsOneWidget);
  });

  testWidgets('typing edits the entry text live', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add trait'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'steady hands');
    await tester.pump();
    expect(last!.last.text, 'steady hands');
  });

  testWidgets('a fresh Novice bogey stays unpinned (ruling 2026-11-21)', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Add trait'));
    await tester.pump();
    await tester.tap(find.byTooltip('Kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bogey'));
    await tester.pumpAndSettle();
    expect(last!.single.kind, 'bogey');
    expect(
      last!.single.pinned,
      isFalse,
      reason: 'a Novice flaw is authored fragile; pinning it would lie',
    );
  });

  testWidgets('a fresh Skilled bogey arrives pinned (§4 default)', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Add trait'));
    await tester.pump();
    await tester.tap(find.byTooltip('Starting tier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skilled — a known habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bogey'));
    await tester.pumpAndSettle();
    expect(last!.single.kind, 'bogey');
    expect(
      last!.single.pinned,
      isTrue,
      reason: 'a bogey the author calls a habit arrives pinned',
    );
  });

  testWidgets('kind change on a written row keeps the author\'s pin', (
    tester,
  ) async {
    await pump(
      tester,
      values: [
        TraitKitEntry(kind: 'boon', text: 'steady hands', pinned: false),
      ],
    );
    await tester.tap(find.byTooltip('Kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bogey'));
    await tester.pumpAndSettle();
    expect(last!.single.kind, 'bogey');
    expect(
      last!.single.pinned,
      isFalse,
      reason:
          'the author unpinned a real '
          'entry; the default is for fresh rows, not a veto',
    );
  });

  testWidgets('the tier menu sets the starting tier, and caps at Skilled', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Add trait'));
    await tester.pump();
    await tester.tap(find.byTooltip('Starting tier'));
    await tester.pumpAndSettle();
    // Seed cap (ruling 8, amended 2026-11-21): exactly two options, and no
    // label says Master — a card seeds a habit, never a mastery. The closed
    // row already reads Novice, so its menu twin makes that one appear twice.
    expect(find.text('Novice — starts faint'), findsNWidgets(2));
    expect(find.text('Skilled — a known habit'), findsOneWidget);
    expect(
      find.textContaining('Master', findRichText: true),
      findsNothing,
      reason: 'the editor must not offer a Master-level seed',
    );
    await tester.tap(find.text('Skilled — a known habit'));
    await tester.pumpAndSettle();
    expect(last!.last.tier, 'developing');
  });

  testWidgets('the closed controls show their value, not just arrows', (
    tester,
  ) async {
    // The maintainer read the shipped editor as hiding everything: tier
    // was a bare chevron, and the kind badge looked like a static label.
    // Both must state what they are with the menu shut.
    await pump(
      tester,
      values: [
        TraitKitEntry(kind: 'bogey', text: 'bad temper', tier: 'established'),
      ],
    );
    expect(
      find.text('Skilled — a known habit'),
      findsOneWidget,
      reason:
          'the closed tier control names the current '
          'tier in full, and a pre-cap established entry '
          'reads as its capped Skilled',
    );
    expect(
      find.text('Bogey'),
      findsOneWidget,
      reason: 'the kind chip reads as a dropdown, and says Bogey',
    );
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
  });

  testWidgets('the pin button toggles', (tester) async {
    await pump(
      tester,
      values: [
        TraitKitEntry(kind: 'bogey', text: 'bad temper', pinned: true),
      ],
    );
    await tester.tap(
      find.byTooltip('Pinned — a seeded flaw never fades. Tap to unpin.'),
    );
    await tester.pump();
    expect(last!.single.pinned, isFalse);
  });

  testWidgets('remove drops the row', (tester) async {
    await pump(
      tester,
      values: [
        TraitKitEntry(kind: 'bogey', text: 'bad temper'),
        TraitKitEntry(kind: 'boon', text: 'steady hands'),
      ],
    );
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump();
    expect(last, hasLength(1));
    expect(last!.single.text, 'steady hands');
  });

  testWidgets('Add stops at six and says so', (tester) async {
    await pump(
      tester,
      values: List.generate(
        6,
        (i) => TraitKitEntry(kind: 'boon', text: 'trait $i'),
      ),
    );
    expect(find.text('6 of 6'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Add — kit is full'),
        matching: find.byType(TextButton),
      ),
    );
    expect(
      button.onPressed,
      isNull,
      reason:
          'ruling 11: the cap is enforced '
          'in the creator, not politely suggested at review',
    );
  });

  testWidgets('a fourth bogey warns before seeding drops it', (tester) async {
    await pump(
      tester,
      values: List.generate(
        4,
        (i) => TraitKitEntry(kind: 'bogey', text: 'bogey $i'),
      ),
    );
    expect(find.textContaining('at most 3 active bogies'), findsOneWidget);
  });
}
