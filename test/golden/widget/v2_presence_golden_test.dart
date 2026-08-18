// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// V2 glance: presence word under TimeStrip. Plan lives on the calendar.
// Sheet work row. Group card dims when Away / At work.

@Tags(['golden'])
@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/widgets/group_member_card.dart';
import 'package:front_porch_ai/ui/widgets/work_row.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

Widget _stack(FakeChatService chat, PresenceWhere where) {
  return SizedBox(
    width: 300,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TimeStrip(chat: chat),
        PresenceWord(where: where),
      ],
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('Chat — With you', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: _stack(chat, PresenceWhere.withYou),
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
    final chat = _GroupCardChat();
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 300,
        child: GroupMemberCard(
          character: CharacterCard(name: 'Mira'),
          chatService: chat,
          avatarColor: const Color(0xFF7A6A4F),
          isNextSpeaker: false,
          isExpanded: false,
          onTap: () {},
        ),
      ),
      group: 'v2',
      name: 'group_away_dim',
      surface: const Size(340, 160),
    );
  });
}

/// Compact card golden. Realism off so we do not need the full group-state
/// surface. Away comes from stance, not from collapsed / not-next.
class _GroupCardChat extends FakeChatService {
  _GroupCardChat() : super(timeOfDay: 'evening', dayCount: 3);

  @override
  String spatialStanceForGroupCharacter(CharacterCard character) =>
      'left the room';
}
