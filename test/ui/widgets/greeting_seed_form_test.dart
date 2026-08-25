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

  testWidgets('desktop seed fields can return to inherit', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    GreetingRealismSeed? live = const GreetingRealismSeed(
      emotionIntensity: 'strong',
      timeOfDay: 'night',
      dayCount: 4,
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
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '4'), '');
    await tester.pumpAndSettle();
    expect(
      live!.dayCount,
      isNull,
      reason: 'empty day number returns to inherit',
    );
    expect(
      live!.dayCount,
      isNot(0),
      reason: 'empty day must write null, not 0',
    );

    await tester.tap(find.text('strong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inherit (mild)').last);
    await tester.pumpAndSettle();
    expect(
      live!.emotionIntensity,
      isNull,
      reason: 'intensity dropdown must offer inherit after a pick',
    );

    await tester.tap(find.text('night'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inherit (morning)').last);
    await tester.pumpAndSettle();
    expect(
      live!.timeOfDay,
      isNull,
      reason: 'time dropdown must offer inherit after a pick',
    );
    expect(live!.dayCount, isNull);
    expect(live!.emotionIntensity, isNull);
    expect(live!.timeOfDay, isNull);
  });

  testWidgets(
    'set strong / night / day 4 then inherit-clear persists all three null',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      GreetingRealismSeed? live = const GreetingRealismSeed();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: GreetingSeedForm(
                    seed: live,
                    onChanged: (next) => setState(() => live = next),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('inherit (mild)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('strong').last);
      await tester.pumpAndSettle();
      expect(live!.emotionIntensity, 'strong');

      await tester.tap(find.text('inherit (morning)').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('night').last);
      await tester.pumpAndSettle();
      expect(live!.timeOfDay, 'night');

      final dayField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'inherit (day 1)',
      );
      await tester.enterText(dayField, '4');
      await tester.pumpAndSettle();
      expect(live!.dayCount, 4);

      await tester.enterText(find.widgetWithText(TextField, '4'), '');
      await tester.pumpAndSettle();
      expect(
        live!.dayCount,
        isNull,
        reason: 'empty day number writes null, not leftover 4 or 0',
      );
      expect(live!.dayCount, isNot(0));

      await tester.tap(find.text('strong'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('inherit (mild)').last);
      await tester.pumpAndSettle();
      expect(live!.emotionIntensity, isNull);

      await tester.tap(find.text('night'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('inherit (morning)').last);
      await tester.pumpAndSettle();
      expect(live!.timeOfDay, isNull);

      expect(live!.emotionIntensity, isNull);
      expect(live!.timeOfDay, isNull);
      expect(live!.dayCount, isNull);
    },
  );

  testWidgets('typed day 0 persist-clears to inherit, not ignored', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    GreetingRealismSeed? live = const GreetingRealismSeed(dayCount: 4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: GreetingSeedForm(
                  seed: live,
                  onChanged: (next) => setState(() => live = next),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dayField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'inherit (day 1)',
    );
    expect(dayField, findsOneWidget);
    await tester.enterText(dayField, '0');
    await tester.pumpAndSettle();
    expect(
      live!.dayCount,
      isNull,
      reason: 'typed 0 must inherit-clear, not keep leftover 4',
    );
    expect(live!.dayCount, isNot(0), reason: '0 is inherit, not calendar day 0');
  });

  testWidgets('bond/trust/needs sliders can return to inherit', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    GreetingRealismSeed? live = const GreetingRealismSeed();

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

    Finder boxFor(String label) {
      return find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is SliderWithInput && w.label == label,
        ),
        matching: find.byType(TextField),
      );
    }

    Future<void> authorBox(String label, String value) async {
      final field = boxFor(label);
      expect(field, findsOneWidget, reason: 'number box for $label');
      await tester.enterText(field, value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    Future<void> inheritBox(String label) async {
      final field = boxFor(label);
      expect(field, findsOneWidget, reason: 'inherit box for $label');
      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    await authorBox('Short-term bond', '20');
    expect(live!.shortTermBond, 20);
    await authorBox('Trust', '10');
    expect(live!.trustLevel, 10);
    await authorBox('Hunger', '25');
    expect(live!.needsBaselineHunger, 25);

    await inheritBox('Short-term bond');
    expect(
      live!.shortTermBond,
      isNull,
      reason: 'bond empty number box writes inherit, not leftover 20 or 0',
    );
    expect(live!.shortTermBond, isNot(0));

    await inheritBox('Trust');
    expect(
      live!.trustLevel,
      isNull,
      reason: 'trust empty number box writes inherit, not leftover 10 or 0',
    );
    expect(live!.trustLevel, isNot(0));

    await inheritBox('Hunger');
    expect(
      live!.needsBaselineHunger,
      isNull,
      reason: 'needs empty number box writes inherit, not leftover 25 or 0',
    );
    expect(live!.needsBaselineHunger, isNot(0));

    await tester.pumpAndSettle();
    expect(live!.shortTermBond, isNull);
    expect(live!.trustLevel, isNull);
    expect(live!.needsBaselineHunger, isNull);
    expect(live!.shortTermBond, isNot(0));
    expect(live!.trustLevel, isNot(0));
    expect(live!.needsBaselineHunger, isNot(0));
  });
}
