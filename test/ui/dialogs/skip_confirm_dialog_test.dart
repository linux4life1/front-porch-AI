// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Did time pass?" on the desktop (#629): the chips the engine offers,
// best guess picked; "No skip" and "Other…"; the button names where the
// clock lands; a failed reading preselects nothing; the dialog closes
// when the question is answered elsewhere. Fits a 400 px window, a short
// one, and 1440 px.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/time_skip/time_skip.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

void main() {
  final night = DateTime.utc(2026, 8, 22, 1, 40);
  const line =
      '*We fell asleep on the couch and slept eight hours before we woke up.*';

  PendingSkip disagrees() => PendingSkip.build(
    line: line,
    reason: SkipAskReason.disagrees,
    clock: night,
    guess: const SkipVerdict(until: 'morning', slept: true),
  );

  /// Opens the dialog for [question]; the answer lands in [answers].
  Future<void> open(
    WidgetTester tester,
    PendingSkip question,
    List<SkipVerdict?> answers, {
    Size size = const Size(1440, 900),
    ValueNotifier<bool>? live,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final changes = live ?? ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await showSkipConfirmDialog(
                  context,
                  question: question,
                  changes: changes,
                  isLive: () => changes.value,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String button(WidgetTester tester) {
    final b = tester.widget<ElevatedButton>(
      find.byKey(const Key('skip-confirm')),
    );
    return (b.child! as Text).data!;
  }

  for (final size in const [Size(400, 760), Size(400, 420), Size(1440, 900)]) {
    testWidgets('the guess is picked, the player picks 8 hours '
        '(${size.width.toInt()}×${size.height.toInt()})', (tester) async {
      final answers = <SkipVerdict?>[];
      await open(tester, disagrees(), answers, size: size);

      expect(find.text('Did time pass?'), findsOneWidget);
      expect(find.text('Next morning · 8:00 AM'), findsOneWidget);
      expect(find.text('8 hours · 9:40 AM'), findsOneWidget);
      expect(find.text('No skip'), findsOneWidget);
      expect(find.text('Other…'), findsOneWidget);
      expect(button(tester), 'Skip to 8:00 AM');
      expect(find.text('Everyone wakes rested.'), findsOneWidget);

      await tester.tap(find.text('8 hours · 9:40 AM'));
      await tester.pump();
      expect(button(tester), 'Skip to 9:40 AM');
      await tester.tap(find.byKey(const Key('skip-confirm')));
      await tester.pumpAndSettle();
      expect(answers, [const SkipVerdict(minutes: 480, slept: true)]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('"No skip" sends without one', (tester) async {
    final answers = <SkipVerdict?>[];
    await open(tester, disagrees(), answers);
    await tester.tap(find.text('No skip'));
    await tester.pump();
    expect(button(tester), 'Send without a skip');
    await tester.tap(find.byKey(const Key('skip-confirm')));
    await tester.pumpAndSettle();
    expect(answers, [SkipVerdict.none]);
  });

  testWidgets('"Other…" reads like /skip and says how when it cannot', (
    tester,
  ) async {
    final answers = <SkipVerdict?>[];
    await open(tester, disagrees(), answers, size: const Size(400, 760));
    await tester.tap(find.text('Other…'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('skip-other-field')), 'soon');
    await tester.pump();
    expect(find.text(kSkipTagUsage), findsOneWidget);
    expect(button(tester), 'Pick one');

    await tester.enterText(find.byKey(const Key('skip-other-field')), '3h');
    await tester.pump();
    expect(button(tester), 'Skip to 4:40 AM');
    await tester.tap(find.byKey(const Key('skip-confirm')));
    await tester.pumpAndSettle();
    expect(answers, [const SkipVerdict(minutes: 180)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed reading picks nothing for the player', (tester) async {
    final answers = <SkipVerdict?>[];
    await open(
      tester,
      PendingSkip.build(
        line: 'We sleep.',
        reason: SkipAskReason.noReading,
        clock: night,
      ),
      answers,
    );
    expect(button(tester), 'Pick one');
    final confirm = tester.widget<ElevatedButton>(
      find.byKey(const Key('skip-confirm')),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('answered elsewhere, the dialog closes with no answer', (
    tester,
  ) async {
    final answers = <SkipVerdict?>[];
    final live = ValueNotifier(true);
    await open(tester, disagrees(), answers, live: live);
    live.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Did time pass?'), findsNothing);
    expect(answers, [null]);
  });
}
