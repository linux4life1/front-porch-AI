// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GreetingSeedForm: Story begins is date+time, {} looks inherit (mild) /
// sliders unset, toggle off/on stashes, fresh enable persists null not {}.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/widgets/slider_with_input.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpForm(
    WidgetTester tester, {
    required GreetingRealismSeed? seed,
    required ValueChanged<GreetingRealismSeed?> onChanged,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GreetingSeedForm(
              seed: seed,
              onChanged: onChanged,
              showNeeds: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty overlay {} looks inherit (mild) and sliders are unset', (
    tester,
  ) async {
    await pumpForm(
      tester,
      seed: const GreetingRealismSeed(),
      onChanged: (_) {},
    );

    expect(find.text('inherit (mild)'), findsWidgets);
    expect(find.text('inherit (morning)'), findsWidgets);
    expect(find.text('moderate'), findsNothing);

    final sliders = tester
        .widgetList<SliderWithInput>(find.byType(SliderWithInput))
        .toList();
    expect(sliders, isNotEmpty);
    for (final slider in sliders) {
      expect(
        slider.unset,
        isTrue,
        reason:
            '{} must not author a moderate / 0 / 80 default on ${slider.label}',
      );
    }
  });

  testWidgets('Story begins has date and time chips', (tester) async {
    await pumpForm(
      tester,
      seed: const GreetingRealismSeed(),
      onChanged: (_) {},
    );

    expect(find.byType(StoryBeginsRow), findsOneWidget);
    expect(find.textContaining('Story begins'), findsOneWidget);
    expect(find.textContaining('Opens at'), findsOneWidget);
  });

  testWidgets('toggle off then on stashes the prior authored seed', (
    tester,
  ) async {
    GreetingRealismSeed? live = const GreetingRealismSeed(
      characterEmotion: 'furious',
      storyStartDate: '1887-06-01',
      storyStartTime: '23:47',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: GreetingSeedForm(
                  seed: live,
                  onChanged: (next) => setState(() => live = next),
                  showNeeds: true,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(live, isNull, reason: 'toggle off persists null (read the room)');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(live, isNotNull);
    expect(live!.characterEmotion, 'furious');
    expect(live!.storyStartDate, '1887-06-01');
    expect(live!.storyStartTime, '23:47');
  });

  testWidgets('fresh enable persists null, not empty {}', (tester) async {
    GreetingRealismSeed? live;
    Object? lastEmitted = 'unset';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: GreetingSeedForm(
                  seed: live,
                  onChanged: (next) {
                    lastEmitted = next;
                    setState(() => live = next);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Story begins'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(
      lastEmitted,
      isNull,
      reason: 'fresh enable must persist null, not {}',
    );
    expect(live, isNull);
    expect(find.byType(StoryBeginsRow), findsOneWidget);
  });
}
