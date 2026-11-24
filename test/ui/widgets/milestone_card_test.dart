// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop milestone card (docs/design/boons-and-bogies.md §7), from the
// approved mockup: the words it shows, group naming, replay, one answer per
// double tap, the bogey-cap line, and reduce motion.

import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/chat_service.dart' show MilestoneView;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/milestone_palette.dart';
import 'package:front_porch_ai/ui/widgets/milestone/milestone.dart';

import '../../helpers/double_tap.dart';

MilestoneView _view({
  String kind = 'new_boon',
  String pill = 'BOON',
  String title = 'New boon',
  String ask = '',
  bool inGroup = false,
}) => MilestoneView(
  id: 'm1',
  kind: kind,
  status: 'pending',
  seen: false,
  title: title,
  pill: pill,
  tierLine: 'Novice · new',
  text: 'catches what falls before it lands',
  receipt: 'Seen in #14 and #18',
  ask: ask,
  ownerName: 'Mira Vale',
  inGroup: inGroup,
  meter: 0.3,
);

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester,
    MilestoneView view, {
    bool replaying = false,
    required Future<MilestoneOutcome> Function(bool) onAnswer,
    bool still = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        // Above the Navigator: the dialog route reads this MediaQuery too.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: const Size(400, 800), disableAnimations: still),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => MilestoneOverlay(
                    view: view,
                    replaying: replaying,
                    onAnswer: onAnswer,
                  ),
                ),
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

  testWidgets('shows the approved words: title, kind, ring, receipt', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      _view(),
      onAnswer: (_) async => MilestoneOutcome.done,
    );
    expect(find.textContaining('Milestone'), findsWidgets);
    expect(find.text('New boon'), findsOneWidget);
    expect(find.text('BOON'), findsOneWidget);
    expect(find.text('catches what falls before it lands'), findsOneWidget);
    expect(find.text('Seen in #14 and #18'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.textContaining('Mira Vale'), findsNothing, reason: '1:1');
  });

  testWidgets('a group card names the member; Master asks and stamps', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      _view(
        kind: 'master_bogey',
        pill: 'BOGEY',
        title: 'Master · bogey',
        ask: 'This has become part of who Mira Vale is. Make it permanent?',
        inGroup: true,
      ),
      onAnswer: (_) async => MilestoneOutcome.done,
    );
    expect(find.textContaining('Mira Vale'), findsWidgets);
    expect(find.text('MASTER'), findsOneWidget);
    expect(find.textContaining('Make it permanent?'), findsOneWidget);
  });

  testWidgets('a replay asks nothing: one Close button', (tester) async {
    await pumpOverlay(
      tester,
      _view(),
      replaying: true,
      onAnswer: (_) async => MilestoneOutcome.done,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(MilestoneOverlay), findsNothing);
  });

  // The repo's create/save rule: a double tap with no frame between writes
  // once. The write itself is guarded where it lands
  // (GrowthMilestones.decide's in-flight set, proven red in
  // growth_milestones_test); this pins the card's side of the contract.
  testWidgets('a double tap on Accept answers once and closes the card', (
    tester,
  ) async {
    var answers = 0;
    await pumpOverlay(
      tester,
      _view(),
      onAnswer: (accept) async {
        answers++;
        expect(accept, isTrue);
        return MilestoneOutcome.done;
      },
    );
    await doubleTapNoFrame(tester, find.text('Accept'));
    await tester.pumpAndSettle();
    expect(answers, 1);
    expect(find.byType(MilestoneOverlay), findsNothing);
  });

  testWidgets('a full bogey cap keeps the card up and says why', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      _view(kind: 'new_bogey', pill: 'BOGEY', title: 'New bogey'),
      onAnswer: (_) async => MilestoneOutcome.bogeyCapFull,
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.byType(MilestoneOverlay), findsOneWidget);
    expect(find.textContaining('already carries three bogies'), findsOneWidget);
  });

  testWidgets('reduce motion paints no celebration', (tester) async {
    await pumpOverlay(
      tester,
      _view(kind: 'master_boon', title: 'Master · boon'),
      onAnswer: (_) async => MilestoneOutcome.done,
    );
    expect(find.byType(GameWidget<MilestoneBurstGame>), findsNothing);
    expect(find.text('MASTER'), findsOneWidget, reason: 'badge static');
  });

  testWidgets('the kind pill stays readable on a light card (4.5:1)', (
    tester,
  ) async {
    for (final view in [
      _view(),
      _view(kind: 'new_bogey', pill: 'BOGEY', title: 'New bogey'),
      _view(kind: 'overcome', pill: 'BOGEY', title: 'Overcome'),
    ]) {
      await pumpOverlay(
        tester,
        view,
        onAnswer: (_) async => MilestoneOutcome.done,
      );
      final pill = find.text(view.pill);
      final context = tester.element(pill);
      expect(Theme.of(context).brightness, Brightness.light);
      final ink = tester.widget<Text>(pill).style!.color!;
      // The pill's fill (accent 22%) over the ring box (accent 10% over the
      // card): the darkest the accent can make what sits behind the word.
      final accent = switch (view.kind) {
        'overcome' => MilestonePalette.overcome,
        'new_bogey' => MilestonePalette.violet,
        _ => MilestonePalette.gold,
      };
      final box = Color.alphaBlend(
        accent.withValues(alpha: 0.10),
        AppColors.cardOf(context),
      );
      final fill = Color.alphaBlend(accent.withValues(alpha: 0.22), box);
      final a = ink.computeLuminance(), b = fill.computeLuminance();
      final ratio = (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: '${view.kind}: $ratio');
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
  });
}
