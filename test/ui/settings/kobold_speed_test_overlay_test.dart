// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Local model card's speed test on the desktop, tapped through: the
// button, the question with how long it takes, the overlay while it runs
// (progress, the step, the time left, what it does, Cancel), the one line it
// ends with, and that line under the button afterwards. Nothing on screen
// names a setting. The test runs the real KoboldSpeedTest; the engine's
// timings are held and released by the test, one at a time.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend.dart';

import '../../golden/support/fakes_services.dart';

/// The engine: each timing waits for the test to let it go, then reports a
/// turn's speeds (reading at [read] tokens a second, writing at 200).
class _Kobold extends FakeKoboldService {
  final gates = <int, Completer<void>>{};
  double read = 1000;
  int holds = 0;

  @override
  Future<void Function()> holdForSpeedTest() async {
    holds++;
    return () => holds--;
  }

  @override
  Future<KoboldSpeed?> timeTurn(int round) async {
    await (gates[round] ??= Completer<void>()).future;
    return (
      read: 2000,
      readSeconds: 2000 / read,
      written: 200,
      writeSeconds: 1.0,
    );
  }
}

const _start = KoboldKnobs(
  batch: 1024,
  mmq: true,
  mmap: true,
  mlock: false,
  flashAttention: true,
);

void main() {
  late _Kobold kobold;
  late KoboldSpeedTest test;
  late List<KoboldKnobs> saved;
  late int putBack;

  setUp(() {
    kobold = _Kobold();
    saved = [];
    putBack = 0;
    test = KoboldSpeedTest(
      kobold: kobold,
      why: () async => null,
      setup: () async => const KoboldSpeedSetup(
        model: '/m/Qwen3-14B.gguf',
        card: 'NVIDIA GeForce RTX 4090',
        backend: 'cuda',
        engine: '1.122.1',
        start: _start,
        facts: KoboldSpeedFacts(
          batches: [512, 1024],
          mmq: true,
          mlock: false,
          flashAttention: true,
        ),
        load: Duration(seconds: 10),
        timing: Duration(seconds: 20),
      ),
      mapFor: (k) async => {'ubatchsize': k.batch},
      loadTrial: (name, config) async => true,
      reloadChat: () async {
        putBack++;
        return null;
      },
      save: (s, best) async => saved.add(best),
      replaces: (s) async => null,
    );
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: KoboldSpeedTestButton(
              test: test,
              model: '/m/Qwen3-14B.gguf',
              phase: KoboldPhase.ready,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> release(WidgetTester tester, int round) async {
    (kobold.gates[round] ??= Completer<void>()).complete();
    await tester.pumpAndSettle();
  }

  String overlayLine(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('speed-test-line'))).data!;

  String screenText(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '',
  ].join(' | ');

  testWidgets('asked first, then followed step by step, then one line; '
      'Cancel stops after the step and puts the model back', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.text('Find the fastest settings for this computer'));
    await tester.pumpAndSettle();

    // Five timings at 30 s each, a reload and a timing, in all.
    expect(
      find.text(
        'This takes about 3 minutes. Replies may start sooner afterwards. '
        'Run it?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('speed-test-run')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('speed-test-progress')), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('About 3 minutes left'), findsOneWidget);
    expect(find.text('Timing how fast replies come now…'), findsOneWidget);
    expect(kobold.holds, 1, reason: "the app's requests wait meanwhile");

    await release(tester, 1);
    expect(find.text('Step 2 of 5'), findsOneWidget);
    expect(
      find.text('Loading the model with other settings, then timing it…'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('speed-test-cancel')));
    await tester.pump();
    expect(find.text('Stopping after this step…'), findsOneWidget);
    await release(tester, 2);

    // The overlay's line, and the same line under the button behind it.
    expect(overlayLine(tester), 'Stopped. Your settings were not changed.');
    expect(
      find.text('Stopped. Your settings were not changed.'),
      findsNWidgets(2),
    );
    expect(putBack, 1);
    expect(saved, isEmpty);
    expect(kobold.holds, 0, reason: 'chat goes again');
    expect(screenText(tester), isNot(contains('MMQ')));
    expect(screenText(tester), isNot(contains('1,024')));

    await tester.tap(find.byKey(const ValueKey('speed-test-done')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local-model-speed-test-line')),
      findsOneWidget,
    );
  });

  testWidgets('a finished test says how much sooner replies come, and the '
      'card keeps saying it', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.text('Find the fastest settings for this computer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('speed-test-run')));
    await tester.pumpAndSettle();
    await release(tester, 1);
    // 512 reads slower: kept at 1,024. Then the other settings, as fast.
    kobold.read = 800;
    await release(tester, 2);
    kobold.read = 1000;
    for (var round = 3; round <= 5; round++) {
      await release(tester, round);
    }
    expect(
      overlayLine(tester),
      'Your current settings were already the fastest.',
    );
    expect(saved, [_start]);
    await tester.tap(find.byKey(const ValueKey('speed-test-done')));
    await tester.pumpAndSettle();
    expect(
      find.text('Your current settings were already the fastest.'),
      findsOneWidget,
    );
  });

  testWidgets('one that cannot run says why, and runs nothing', (tester) async {
    test = KoboldSpeedTest(
      kobold: kobold,
      why: () async => 'Start the model first, then run the test.',
      setup: () async => null,
      mapFor: (k) async => {},
      loadTrial: (name, config) async => true,
      reloadChat: () async => null,
      save: (s, best) async {},
      replaces: (s) async => null,
    );
    await pumpCard(tester);
    expect(
      find.text('Start the model first, then run the test.'),
      findsOneWidget,
    );
    final button = tester.widget<Widget>(
      find.byKey(const ValueKey('local-model-speed-test')),
    );
    expect((button as dynamic).onPressed, isNull);
    expect(kobold.holds, 0);
  });
}
