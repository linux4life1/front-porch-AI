// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// V2 glance: presence word under TimeStrip, above TodayLine.
// Sheet work row. Group card dims when Away / At work.

@Tags(['golden'])
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/today_line.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/work_row.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

Widget _stack(FakeChatService chat, PresenceWhere where, {String? today}) {
  return SizedBox(
    width: 300,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TimeStrip(chat: chat),
        PresenceWord(where: where),
        TodayLine(enabled: true, text: today),
      ],
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('Chat — With you + today line', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: _stack(
        chat,
        PresenceWhere.withYou,
        today: 'Get Saturday’s errands done before Tuesday’s review.',
      ),
      group: 'v2',
      name: 'with_you',
      surface: const Size(340, 200),
    );
  });

  testWidgets('Chat — Away, strip still live, no today line', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: _stack(chat, PresenceWhere.away),
      group: 'v2',
      name: 'away',
      surface: const Size(340, 180),
    );
  });

  testWidgets('Chat — At work (derived)', (tester) async {
    final chat = FakeChatService(timeOfDay: 'afternoon', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: _stack(chat, PresenceWhere.atWork),
      group: 'v2',
      name: 'at_work',
      surface: const Size(340, 180),
    );
  });

  testWidgets('Sheet — occupation + hours', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 300,
        child: WorkRow(
          occupation: 'lighthouse keeper',
          hours: 'dawn–dusk',
          onOccupationChanged: (_) {},
          onHoursChanged: (_) {},
        ),
      ),
      group: 'v2',
      name: 'work_row',
      surface: const Size(340, 180),
    );
  });

  testWidgets('Group — Away dims the compact card', (tester) async {
    const word = PresenceWord(where: PresenceWhere.away);
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 300,
        child: Opacity(
          opacity: word.dimCard ? 0.45 : 1,
          child: Row(
            children: [
              Builder(
                builder: (context) => Text(
                  'Mira',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              word,
            ],
          ),
        ),
      ),
      group: 'v2',
      name: 'group_away_dim',
      surface: const Size(340, 80),
    );
  });
}
