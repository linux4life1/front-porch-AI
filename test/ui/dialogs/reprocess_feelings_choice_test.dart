// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Manual Reprocess offers a choice: Needs (today's critique pass, the
// default) or Feelings (the Realism judges asked again about the user's
// line). The real dialog over a real ChatService; tapping Feelings and
// "Score again" runs the real re-score and the reply's chips change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show kFeelingsUnscoredMeta;
import 'package:front_porch_ai/ui/dialogs/reprocess_needs_dialog.dart';

import '../../helpers/reprocess_needs_harness.dart';

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

/// Taps [label] in real time, so the re-score it starts (eval stagger and
/// stream debounce are timers; the database answers in real time) runs on
/// the real clock, then waits for the pass to let go of the turn.
Future<void> _tapAndSettle(
  WidgetTester tester,
  ReprocessHarness h,
  String label,
) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(label));
    for (var i = 0; i < 400 && h.chat.isSettlingTurn; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await drainMicrotasks();
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  testWidgets('both on offer: Needs is the default; Feelings re-scores the '
      'reply and says so', (tester) async {
    await _withHarness(tester, (h) async {
      final i = (await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      ))!;
      // Make the reply read as a failed score, as the live report did, so
      // the only way back to a real score is the pass this test taps.
      final meta = h.chat.messages[i].activeMetadata!;
      meta
        ..remove('bond_delta')
        ..remove('trust_delta')
        ..[kFeelingsUnscoredMeta] = true;

      await _openDialog(tester, h, i);
      expect(find.text(kReprocessChoicePrompt), findsOneWidget);
      expect(find.text('Reprocess Needs Deltas'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Reprocess'), findsOneWidget);

      await tester.tap(find.text(kReprocessChoiceFeelings));
      await tester.pumpAndSettle();
      expect(find.text(kReprocessFeelingsTitle), findsOneWidget);
      expect(find.text(reprocessFeelingsIntro('Mara')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilterChip), findsNothing);

      await _tapAndSettle(tester, h, kReprocessFeelingsButton);
      expect(find.text(kReprocessFeelingsDone), findsOneWidget);
      final after = h.chat.messages[i].activeMetadata!;
      expect(after[kFeelingsUnscoredMeta], isNull);
      expect(after['trust_delta'], 1, reason: 'the scripted judge says +1');
      expect(after['bond_delta'], 0);
      expect(h.llm.reprocessPrompts, isEmpty, reason: 'Needs was not run');

      // Back to Needs: today's sheet, unchanged.
      await _openDialog(tester, h, i);
      await tester.tap(find.text(kReprocessChoiceNeeds));
      await tester.pumpAndSettle();
      expect(find.text('Reprocess Needs Deltas'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(minutes: 1)));

  testWidgets('an older reply offers Needs only, with no choice row', (
    tester,
  ) async {
    await _withHarness(tester, (h) async {
      final first = (await tester.runAsync(
        () => h.oneToOneWithStampedReply(needsCard('Mara')),
      ))!;
      await tester.runAsync(() async {
        await h.chat.sendMessage('And tomorrow?');
        await h.settleTurn();
      });
      expect(h.chat.reprocessFeelingsTargetFor(first), isNull);
      await _openDialog(tester, h, first);
      expect(find.text(kReprocessChoicePrompt), findsNothing);
      expect(find.text(kReprocessChoiceFeelings), findsNothing);
      expect(find.text('Reprocess Needs Deltas'), findsOneWidget);
    });
  }, timeout: const Timeout(Duration(minutes: 1)));
}
