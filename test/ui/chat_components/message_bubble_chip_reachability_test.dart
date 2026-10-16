// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// CHIP SURFACES THAT WERE UNREACHABLE OR BROKEN FOR THE USERS WHO NEEDED THEM
// MOST.
//
// 1. Pockets & Wardrobe receipts. Pockets answers to its OWN switch and runs
//    with the Realism Engine off (docs/design/feature-independence.md), so a
//    message can carry `pocket_changes` and no realism/needs keys whatsoever.
//    `_buildRealismIndicator`'s early return only inspected the realism keys,
//    so for exactly those users the receipt chip was built and then thrown
//    away — the one surface that says what the bookkeeping pass decided.
//
// 2. Manual Reprocess / Revert-reprocess. Both pills lived INSIDE the needs-
//    chip branch of the layout, so they only existed on a turn that produced
//    at least one non-zero need delta. A reprocess whose correction nets to
//    zero writes an empty `needs_deltas` while keeping the
//    `needs_deltas_pre_reprocess` stash — no needs chip, therefore no Revert,
//    on the message the user had just changed. The web twin (ChipsRow.tsx)
//    renders the pills as a sibling of both rows; desktop now matches.
//
// 3. A sentence-length receipt overflowed its own chip. The classic row is a
//    Wrap, but each receipt chip was an unbounded Text in a min-size Row, so a
//    single receipt wider than the bubble painted the overflow stripe across
//    the reply.
//
// All proven to fail first: restoring the pre-fix early-return condition
// reds test 1, re-nesting the pills under `needsChipList.isNotEmpty` reds
// tests 2 and 3, and restoring the unbounded receipt Text reds the long
// receipt test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

StorageService _storage() {
  SharedPreferences.setMockInitialValues({});
  return StorageService();
}

void main() {
  setupPathProviderMock();

  Future<void> pumpBubble(
    WidgetTester tester, {
    required ChatMessage message,
    double width = 680,
  }) async {
    final character = CharacterCard(name: 'Aria Vale');
    final chat = FakeChatService(
      activeCharacter: character,
      messages: [message],
    );
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<StorageService>.value(value: storage),
              ChangeNotifierProvider<TtsService>.value(value: tts),
              ChangeNotifierProvider<ChatService>.value(value: chat),
              ChangeNotifierProvider<UserPersonaService>.value(
                value: FakeUserPersonaService(),
              ),
            ],
            child: SizedBox(
              width: width,
              // index 0 == messages.length - 1, i.e. the last message, which
              // is what the reprocess pills require.
              child: MessageBubble(
                message: message,
                index: 0,
                character: character,
                chatService: chat,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'a pockets receipt is shown even when the message carries no realism '
    'or needs metadata at all (Realism Engine off, Pockets on)',
    (tester) async {
      await pumpBubble(
        tester,
        message: ChatMessage(
          text: '*She scoops the car keys off the rail.*',
          sender: 'Aria Vale',
          isUser: false,
          metadata: const {
            'pocket_changes': ['picked up: car keys'],
          },
        ),
      );

      expect(find.text('picked up: car keys'), findsOneWidget);
    },
  );

  testWidgets(
    'Manual Reprocess and Revert stay reachable when every need delta is '
    'zero (the state a reprocess that nets to zero leaves behind)',
    (tester) async {
      await pumpBubble(
        tester,
        message: ChatMessage(
          text: '"I already ate," she said.',
          sender: 'Aria Vale',
          isUser: false,
          metadata: const {
            // A classic chip exists, so the bubble renders — but the needs
            // row is empty, which used to swallow both pills.
            'emotion_label': 'wistful',
            'needs_deltas': <String, dynamic>{},
            'needs_deltas_pre_reprocess': {
              'hunger': {'delta': -6, 'reason': 'skipped lunch'},
            },
            'realism_state': {
              'needs': {'hunger': 62},
            },
          },
        ),
      );

      expect(find.text('Manual Reprocess'), findsOneWidget);
      expect(find.text('Revert reprocess'), findsOneWidget);
    },
  );

  testWidgets(
    'the pills render with no chips at all when every delta filtered to zero',
    (tester) async {
      await pumpBubble(
        tester,
        message: ChatMessage(
          text: '"Nothing changed," she said.',
          sender: 'Aria Vale',
          isUser: false,
          metadata: const {
            'needs_deltas': {
              'hunger': {'delta': 0, 'reason': 'no change'},
            },
            'realism_state': {
              'needs': {'hunger': 62},
            },
          },
        ),
      );

      expect(find.text('Manual Reprocess'), findsOneWidget);
      expect(find.text('Revert reprocess'), findsNothing);
    },
  );

  testWidgets(
    'a long pockets receipt ellipsizes inside a narrow bubble instead of '
    'overflowing it, and keeps the full text in its tooltip',
    (tester) async {
      const receipt =
          'put on: old, too-tight black tank top (clinging to heavy, sore '
          'skin; damp and sweat-soaked from the long walk home in the heat)';
      await pumpBubble(
        tester,
        width: 320,
        message: ChatMessage(
          text: '*She tugs the tank top on.*',
          sender: 'Aria Vale',
          isUser: false,
          metadata: const {
            'pocket_changes': [receipt],
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(receipt), findsOneWidget);
      expect(find.byTooltip('Pockets & Wardrobe: $receipt'), findsOneWidget);
    },
  );

  testWidgets('a message with nothing to report still renders no indicator', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      message: ChatMessage(
        text: '"Evening," she said.',
        sender: 'Aria Vale',
        isUser: false,
        metadata: const {'pocket_changes': <String>[]},
      ),
    );

    expect(find.text('Manual Reprocess'), findsNothing);
    expect(find.byIcon(Icons.checkroom_outlined), findsNothing);
  });
}
