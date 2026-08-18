// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Signed PlanLines goldens only. No Plans / Wings it. No PlanHabitChips.

@Tags(['golden'])
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/calendar_today_hold.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/today_line.dart';
import 'package:front_porch_ai/ui/widgets/plan_lines_editor.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

void _noop() {}

void main() {
  setupPathProviderMock();

  testWidgets('Calendar — today hold under the date', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const SizedBox(
        width: 300,
        child: CalendarTodayHold(
          enabled: true,
          text: 'Get Saturday’s errands done before Tuesday’s review.',
          onAbandon: _noop,
        ),
      ),
      group: 'planner',
      name: 'calendar_today_hold',
      surface: const Size(340, 160),
    );
  });

  testWidgets('Chat — no line, strip only', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TimeStrip(chat: chat),
            const TodayLine(enabled: true, text: null),
          ],
        ),
      ),
      group: 'planner',
      name: 'time_strip_only',
      surface: const Size(340, 160),
    );
  });

  testWidgets('Sheet — two plan lines plus add', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 300,
        child: PlanLinesEditor(
          enabled: true,
          values: const [
            'Get Saturday’s errands done before Tuesday’s review.',
            'Finish the lighthouse log before the tide turns.',
          ],
          onChanged: (_) {},
        ),
      ),
      group: 'planner',
      name: 'plan_lines_list',
      surface: const Size(340, 280),
    );
  });

  testWidgets('Sheet — feature off shrinks the list', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 300,
        child: PlanLinesEditor(
          enabled: false,
          values: const [
            'Get Saturday’s errands done before Tuesday’s review.',
          ],
          onChanged: (_) {},
        ),
      ),
      group: 'planner',
      name: 'plan_lines_off',
      surface: const Size(340, 80),
    );
  });
}
