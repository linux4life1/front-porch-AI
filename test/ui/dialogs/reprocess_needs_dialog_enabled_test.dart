// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Desktop "Reprocess Needs Deltas" dialog shows only the speaker's ENABLED
// needs (/workspace/sow/rn-spec.md item 4). The real dialog is opened over a
// real ChatService (drift DB + scripted model), so what it offers comes from
// the real card and the real resolver, not from a fake.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';
import 'package:front_porch_ai/ui/dialogs/reprocess_needs_dialog.dart';

import '../../golden/support/fakes.dart';

import '../../helpers/reprocess_needs_harness.dart';

const _labels = {
  'hunger': 'Hunger',
  'bladder': 'Bladder',
  'energy': 'Energy',
  'social': 'Social',
  'fun': 'Fun',
  'hygiene': 'Hygiene',
  'comfort': 'Comfort',
};

Future<void> _withHarness(
  WidgetTester tester,
  Future<void> Function(ReprocessHarness h) body,
) async {
  final h = ReprocessHarness();
  await tester.runAsync(() => h.boot());
  try {
    await body(h);
  } finally {
    await tester.runAsync(() => h.dispose());
  }
}

Future<void> _openDialog(
  WidgetTester tester,
  ReprocessHarness h,
  int index,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ChatService>.value(
      value: h.chat,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReprocessNeedsDialog(context, index),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Set<String> _offeredChipLabels(WidgetTester tester) => {
  for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip)))
    ((chip.label as Text).data ?? ''),
};

/// AMENDMENT 2 items 4-5: null resolver at open = ONE state, ONE string, no
/// {name}, and exactly one button (Close): no Cancel, no Reprocess, no
/// critique box, no chips.
void _expectNullState() {
  expect(
    find.text("There's nothing to reprocess for this message."),
    findsOneWidget,
  );
  expect(find.text('Close'), findsOneWidget);
  expect(find.text('Cancel'), findsNothing);
  expect(find.text('Reprocess'), findsNothing);
  expect(find.byType(TextField), findsNothing);
  expect(find.byType(FilterChip), findsNothing);
  final dialogButtons = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(dialogButtons, findsOneWidget);
}

Future<void> _pumpLastBubble(WidgetTester tester, ReprocessHarness h) async {
  final tts = FakeTtsService();
  addTearDown(tts.dispose);
  final index = h.chat.messages.length - 1;
  // Providers sit ABOVE MaterialApp, as in the app (main.providers.dart), so
  // the dialog route can read ChatService like it does in production.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: h.storage),
        ChangeNotifierProvider<TtsService>.value(value: tts),
        ChangeNotifierProvider<ChatService>.value(value: h.chat),
        ChangeNotifierProvider<UserPersonaService>.value(
          value: FakeUserPersonaService(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: MessageBubble(
                message: h.chat.messages[index],
                index: index,
                character: h.chat.activeCharacter!,
                chatService: h.chat,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  testWidgets('C1 Hygiene+Fun off: exactly the 5 enabled chips, the off '
      'ones hidden (not greyed)', (tester) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(
          needsCard('Mara', needsOff: ['hygiene', 'fun']),
        ),
      );
      await _openDialog(tester, h, i!);
      expect(find.byType(FilterChip), findsNWidgets(5));
      expect(_offeredChipLabels(tester), {
        'Hunger',
        'Bladder',
        'Energy',
        'Social',
        'Comfort',
      });
      expect(find.text('Hygiene'), findsNothing);
      expect(find.text('Fun'), findsNothing);
    });
  });

  testWidgets('C2 exact helper copy: nothing selected, then one selected', (
    tester,
  ) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(
          needsCard('Mara', needsOff: ['hygiene', 'fun']),
        ),
      );
      await _openDialog(tester, h, i!);
      expect(
        find.text('Nothing selected — every need shown here is re-evaluated.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Energy'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Only the selected needs change. The others keep their current '
          'deltas.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('C3 exactly one enabled: no "Limit to these needs" block, the '
      'one-line message, and an empty scope is submitted', (tester) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(
          needsCard(
            'Mara',
            needsOff: kAllNeeds.where((n) => n != 'hunger').toList(),
          ),
        ),
      );
      await _openDialog(tester, h, i!);
      expect(
        find.text(
          'Only Hunger is on for Mara, so only Hunger is re-evaluated.',
        ),
        findsOneWidget,
      );
      expect(find.text('Limit to these needs'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);

      await tester.enterText(find.byType(TextField), 'She ate; hunger up.');
      await tester.tap(find.text('Reprocess'));
      await tester.runAsync(() => h.settleTurn());
      await tester.pump();
      await tester.runAsync(() => drainMicrotasks(200));
      await tester.pump();
      // The dialog's own success copy for an EMPTY scope (a non-empty scope
      // reads "Reprocessed <keys> with your critique.").
      expect(
        find.text('Needs deltas reprocessed with your critique.'),
        findsOneWidget,
      );
      expect(askedDeltaKeys(h.llm.reprocessPrompts.single), {'hunger'});
    });
  });

  testWidgets('C4 card now has every need off (stale open): the one null '
      'string, Close only', (tester) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      );
      h.chat.activeCharacter!.frontPorchExtensions!.needsOff = List<String>.of(
        kAllNeeds,
      );
      await _openDialog(tester, h, i!);
      _expectNullState();
    });
  });

  testWidgets('C7 Needs switched off after the pill rendered: tapping the '
      'stale pill opens the one null string, Close only', (tester) async {
    await _withHarness(tester, (h) async {
      await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      );
      await _pumpLastBubble(tester, h);
      expect(find.text('Manual Reprocess'), findsOneWidget);
      // Flip Needs off with the pill still on screen, then tap it before any
      // rebuild: the dialog must re-read the resolver on open.
      await tester.runAsync(() => h.chat.setNeedsSimEnabled(false));
      await tester.tap(find.text('Manual Reprocess'), warnIfMissed: false);
      await tester.pumpAndSettle();
      _expectNullState();
    });
  });

  testWidgets('C5 selecting then submitting never sends a disabled need', (
    tester,
  ) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(
          needsCard('Mara', needsOff: ['hygiene', 'fun']),
        ),
      );
      await _openDialog(tester, h, i!);
      for (final label in ['Hygiene', 'Energy']) {
        final f = find.widgetWithText(FilterChip, label);
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f);
          await tester.pumpAndSettle();
        }
      }
      await tester.enterText(find.byType(TextField), 'Rested; energy up.');
      await tester.tap(find.text('Reprocess'));
      await tester.runAsync(() => h.settleTurn());
      await tester.pump();
      expect(askedDeltaKeys(h.llm.reprocessPrompts.single), {'energy'});
    });
  });

  testWidgets('C6 group: Ayla (Social off) is offered 6 chips, Bram all 7', (
    tester,
  ) async {
    await _withHarness(tester, (h) async {
      final r = await tester.runAsync(() => h.groupWithTwoReplies());
      final (a, b) = r!;
      await _openDialog(tester, h, a);
      expect(
        _offeredChipLabels(tester),
        _labels.values.toSet().difference({'Social'}),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _openDialog(tester, h, b);
      expect(_offeredChipLabels(tester), _labels.values.toSet());
    });
  });

  testWidgets('K1 a ticked need turned off while the dialog is open is not '
      'submitted', (tester) async {
    await _withHarness(tester, (h) async {
      final i = await tester.runAsync(
        () => h.oneToOneWithStampedReply(
          needsCard('Mara', needsOff: ['hygiene', 'fun']),
        ),
      );
      await _openDialog(tester, h, i!);
      await tester.tap(find.widgetWithText(FilterChip, 'Hunger'));
      await tester.pumpAndSettle();

      // Hunger is switched off on the card while the sheet is open; any
      // ChatService notify makes the dialog re-read the resolver.
      h.chat.activeCharacter!.frontPorchExtensions!.needsOff = [
        'hygiene',
        'fun',
        'hunger',
      ];
      await tester.runAsync(() => h.chat.setNeedsSimEnabled(true));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilterChip, 'Hunger'),
        findsNothing,
        reason: 'precondition: the rebuilt dialog hides the now-off need',
      );

      await tester.enterText(find.byType(TextField), 'Rested; energy up.');
      await tester.tap(find.text('Reprocess'));
      await tester.runAsync(() => h.settleTurn());
      await tester.pump();
      await tester.runAsync(() => drainMicrotasks(200));
      await tester.pump();

      // The only way the service refuses here is a scope holding the hidden
      // 'hunger' key (its intersection with the enabled set is empty).
      expect(
        find.text(
          'Reprocess received no response from the model. Original deltas '
          'preserved.',
        ),
        findsNothing,
        reason: 'the dialog submitted the hidden, now-off "hunger" key',
      );
      expect(h.llm.reprocessPrompts, hasLength(1));
      expect(
        askedDeltaKeys(h.llm.reprocessPrompts.single),
        isNot(contains('hunger')),
      );
    });
  });
}
