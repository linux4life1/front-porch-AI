// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chrome must survive three axes — screen, window, and sidebar width —
// without ellipsizing period/clock or accordion titles that still have room.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/porch_accordion.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../../golden/support/fakes.dart';

Future<void> _pumpTight(
  WidgetTester tester,
  Widget child, {
  double width = 180,
}) async {
  await tester.binding.setSurfaceSize(Size(width + 40, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TimeStrip at a tight width keeps Morning, clock, and date whole', (
    tester,
  ) async {
    final chat = FakeChatService(timeOfDay: 'morning', dayCount: 3);
    addTearDown(chat.dispose);

    await _pumpTight(tester, TimeStrip(chat: chat), width: 180);

    final clock = chat.timeService.displayClock;
    final date =
        '${chat.timeService.displayShortDate} · Day ${chat.timeService.dayCount}';

    expect(find.text('Morning'), findsOneWidget);
    expect(find.text(clock), findsOneWidget);
    expect(find.text(date), findsOneWidget);
    expect(find.textContaining('Morning 10'), findsNothing);

    final period = tester.widget<Text>(find.text('Morning'));
    expect(period.overflow, isNot(TextOverflow.ellipsis));
    final clockText = tester.widget<Text>(find.text(clock));
    expect(clockText.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('TimeStrip keeps Late Morning whole when the pane is tight', (
    tester,
  ) async {
    final chat = FakeChatService(timeOfDay: 'late_morning', dayCount: 2);
    addTearDown(chat.dispose);

    await _pumpTight(tester, TimeStrip(chat: chat), width: 180);

    expect(find.text('Late Morning'), findsOneWidget);
    expect(find.text(chat.timeService.displayClock), findsOneWidget);
    final period = tester.widget<Text>(find.text('Late Morning'));
    expect(period.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets(
    'PorchAccordion titles stay whole at a width Spacer used to steal',
    (tester) async {
      const titles = ['Character State', 'Journal & Memory', 'Objectives'];
      await tester.binding.setSurfaceSize(const Size(320, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                // Default sidebar (~300) minus trailing switch: the old Spacer
                // split remaining width 1:1 and ellipsized these titles.
                width: 260,
                child: Column(
                  children: [
                    for (final title in titles)
                      PorchAccordion(
                        id: title,
                        emoji: '🎭',
                        title: title,
                        subtitle: 'Fond · Trusting · Evening',
                        accent: AppColors.porchTerracottaOf(context),
                        trailing: Switch(value: true, onChanged: (_) {}),
                        child: const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final title in titles) {
        expect(find.text(title), findsOneWidget);
      }
    },
  );
}
