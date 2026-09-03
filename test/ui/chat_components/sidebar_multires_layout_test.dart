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
import 'package:front_porch_ai/ui/widgets/needs_bar.dart';

import '../../golden/support/fakes.dart';

Future<void> _pumpTight(
  WidgetTester tester,
  Widget child, {
  double width = 180,
  double height = 400,
}) async {
  await tester.binding.setSurfaceSize(Size(width + 40, height));
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

    await _pumpTight(
      tester,
      TimeStrip(chat: chat),
      width: SidebarTokens.minWidth,
    );

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

    await _pumpTight(
      tester,
      TimeStrip(chat: chat),
      width: SidebarTokens.minWidth,
    );

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
          builder: (context) => Padding(
            // SidebarBody ListView(padding: EdgeInsets.all(12)).
            padding: const EdgeInsets.all(12),
            child: Column(
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
                    // IconButton. Product nest is ListView pad 12 + header
                    // pad 10. Live 214 letter-wrapped Character; 230 is
                    // the floor for whole-word wrap with this trailing.
                    trailing: _characterStateTrailing(),
                    child: const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
        width: SidebarTokens.minWidth,
        height: 500,
      );

      for (final title in titles) {
        _assertTitleWraps(tester, title);
      }
    },
  );

  testWidgets(
    'NeedsGrid at sidebar min inside ListView pad has no overflow at 100%',
    (tester) async {
      const needs = {
        'hunger': 100,
        'bladder': 100,
        'energy': 100,
        'social': 40,
        'fun': 88,
        'hygiene': 62,
        'comfort': 30,
      };

      final overflows = await _overflowsDuring(tester, () async {
        await _pumpTight(
          tester,
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(12),
              child: PorchAccordion(
                id: 'needs',
                emoji: '🎭',
                title: 'Character State',
                accent: AppColors.porchTerracottaOf(context),
                initiallyExpanded: true,
                trailing: _characterStateTrailing(),
                child: const NeedsGrid(needs: needs),
              ),
            ),
          ),
          width: SidebarTokens.minWidth,
          height: 800,
        );
      });

      expect(
        overflows,
        isEmpty,
        reason:
            'NeedsGrid overflowed at minWidth ${SidebarTokens.minWidth} '
            'inside ListView pad 12. overflow=$overflows',
      );
      expect(find.text('100%'), findsWidgets);
      for (final el in find.text('100%').evaluate()) {
        final para = el.renderObject! as RenderParagraph;
        expect(para.didExceedMaxLines, isFalse);
      }
    },
  );

  testWidgets(
    'inner SidebarSubHeader words fit at sidebar min inside ListView pad',
    (tester) async {
      final cases = <(String, Widget)>[
        ('Memory (RAG)', _memoryTrailing()),
        ('Growth · Flora', _growthTrailing()),
      ];

      for (final (label, trailing) in cases) {
        await _pumpTight(
          tester,
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(12),
              child: PorchAccordion(
                id: label,
                emoji: '📖',
                title: 'Journal & Memory',
                accent: AppColors.porchHoneyOf(context),
                initiallyExpanded: true,
                child: SidebarSubHeader(
                  icon: Icons.flag,
                  label: label,
                  accent: AppColors.porchHoneyOf(context),
                  trailing: trailing,
                ),
              ),
            ),
          ),
          width: SidebarTokens.minWidth,
          height: 400,
        );

        _assertLabelWordsFit(tester, label);
      }
    },
  );

  testWidgets(
    '4K window pumps keep titles whole with no overflow (no PNG goldens)',
    (tester) async {
      const windows = [Size(2560, 1440), Size(3840, 2160)];
      const sidebars = [230.0, 300.0];
      const titles = ['Character State', 'Journal & Memory', 'Objectives'];

      for (final window in windows) {
        for (final sidebarWidth in sidebars) {
          final chat = FakeChatService(timeOfDay: 'morning', dayCount: 3);
          addTearDown(chat.dispose);

          final overflows = await _overflowsDuring(tester, () async {
            await tester.binding.setSurfaceSize(window);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
                home: Scaffold(
                  body: Row(
                    children: [
                      const Spacer(),
                      SizedBox(
                        width: sidebarWidth,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final title in titles)
                              Builder(
                                builder: (context) => PorchAccordion(
                                  id: title,
                                  emoji: '🎭',
                                  title: title,
                                  subtitle: 'Fond · Trusting · Evening',
                                  accent: AppColors.porchTerracottaOf(context),
                                  initiallyExpanded: title == 'Character State',
                                  trailing: _characterStateTrailing(),
                                  child: title == 'Character State'
                                      ? TimeStrip(chat: chat)
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          });

          expect(
            overflows,
            isEmpty,
            reason:
                'overflow at window ${window.width.toInt()}x'
                '${window.height.toInt()} sidebar '
                '${sidebarWidth.toInt()}: $overflows',
          );
          for (final title in titles) {
            _assertTitleWraps(tester, title);
          }
        }
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

Widget _memoryTrailing() {
  return SizedBox(
    height: 28,
    child: FittedBox(child: Switch(value: true, onChanged: (_) {})),
  );
}

Widget _growthTrailing() {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.settings, size: 14),
        visualDensity: VisualDensity.compact,
        tooltip: 'Growth settings',
        onPressed: () {},
      ),
      SizedBox(
        height: 28,
        child: FittedBox(child: Switch(value: true, onChanged: (_) {})),
      ),
    ],
  );
}

Future<List<String>> _overflowsDuring(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final overflows = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.toLowerCase().contains('overflowed')) {
      overflows.add(msg.split('\n').first);
    } else {
      old?.call(details);
    }
  };
  try {
    await body();
    final taken = tester.takeException();
    if (taken != null) {
      final msg = taken.toString();
      if (msg.toLowerCase().contains('overflowed')) {
        overflows.add(msg.split('\n').first);
      } else {
        fail('unexpected exception: $taken');
      }
    }
  } finally {
    FlutterError.onError = old;
  }
  return overflows;
}

void _assertLabelWordsFit(WidgetTester tester, String label) {
  expect(find.text(label), findsOneWidget);
  final text = tester.widget<Text>(find.text(label));
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
  expect(paragraph.didExceedMaxLines, isFalse);
  final leftover = paragraph.constraints.maxWidth;
  final style = DefaultTextStyle.of(
    tester.element(find.text(label)),
  ).style.merge(text.style);
  for (final word in label.split(' ')) {
    if (word.isEmpty) continue;
    final wordPainter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(
      wordPainter.width,
      lessThanOrEqualTo(leftover + 0.5),
      reason:
          '"$word" of "$label" must fit in remaining label width '
          '(${leftover.toStringAsFixed(1)}px); '
          'word is ${wordPainter.width.toStringAsFixed(1)}px',
    );
  }
}

void _assertTitleWraps(WidgetTester tester, String title) {
  expect(find.text(title), findsOneWidget);
  final text = tester.widget<Text>(find.text(title));
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(text.maxLines, anyOf(isNull, greaterThanOrEqualTo(2)));
  final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
  expect(paragraph.didExceedMaxLines, isFalse);
  // size.width shrinks to the laid-out string; maxWidth is leftover after
  // ListView pad + header pad + chevron/emoji/trailing.
  final leftover = paragraph.constraints.maxWidth;
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
      lessThanOrEqualTo(leftover + 0.5),
      reason:
          '"$word" of "$title" must fit in remaining title width '
          '(${leftover.toStringAsFixed(1)}px); '
          'word is ${wordPainter.width.toStringAsFixed(1)}px',
    );
  }
}
