// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chrome must survive three axes — screen, window, and sidebar width —
// without ellipsizing period/clock or accordion titles that still have room.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/porch_accordion.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_tokens.dart';
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
      theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
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
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
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
        _assertTitleWraps(tester, title);
      }
    },
  );

  testWidgets(
    'PorchAccordion titles wrap at sidebar min with Character State trailing',
    (tester) async {
      const titles = ['Character State', 'Journal & Memory', 'Objectives'];
      await _pumpTight(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              for (final title in titles)
                PorchAccordion(
                  id: title,
                  emoji: '🎭',
                  title: title,
                  subtitle: 'Fond · Trusting · Evening',
                  accent: AppColors.porchTerracottaOf(context),
                  // Real Character State trailing (character_state_group
                  // 122-157): 24-tall FittedBox Switch PLUS compact tune
                  // IconButton. At 150 that chrome left ~28px for the title
                  // — under "Character" (~60) and "Objectives" (~64) at 13
                  // bold, so the string clipped. Product path snaps closed
                  // below SidebarTokens.minWidth; 150 is unreachable.
                  trailing: _characterStateTrailing(),
                  child: const SizedBox.shrink(),
                ),
            ],
          ),
        ),
        width: SidebarTokens.minWidth,
      );

      for (final title in titles) {
        _assertTitleWraps(tester, title);
      }
    },
  );
}

/// Character State's header trailing: FittedBox Switch + compact tune gear.
Widget _characterStateTrailing() {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 24,
        child: FittedBox(child: Switch(value: true, onChanged: (_) {})),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 15,
        icon: const Icon(Icons.tune),
        onPressed: () {},
      ),
    ],
  );
}

void _assertTitleWraps(WidgetTester tester, String title) {
  expect(find.text(title), findsOneWidget);
  final text = tester.widget<Text>(find.text(title));
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(text.maxLines, anyOf(isNull, greaterThanOrEqualTo(2)));
  final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
  expect(paragraph.didExceedMaxLines, isFalse);
  final style = DefaultTextStyle.of(
    tester.element(find.text(title)),
  ).style.merge(text.style);
  for (final word in title.split(' ')) {
    final wordPainter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(
      wordPainter.width,
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason:
          '"$word" of "$title" must fit in remaining title width '
          '(${paragraph.size.width.toStringAsFixed(1)}px)',
    );
  }
}
