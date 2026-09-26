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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
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

ChatMessage _stamped() => ChatMessage(
  text: '"Evening," she said.',
  sender: 'Aria Vale',
  isUser: false,
  metadata: const {
    'needs_deltas': {
      'hunger': {'delta': -2, 'reason': 'scene'},
    },
    'realism_state': {
      'needs': {'hunger': 62},
    },
  },
);

void main() {
  setupPathProviderMock();

  Future<void> pumpBubble(
    WidgetTester tester, {
    required CharacterCard character,
    bool needsSimEnabled = true,
  }) async {
    final message = _stamped();
    final chat = FakeChatService(
      activeCharacter: character,
      messages: [message],
      needsSimEnabled: needsSimEnabled,
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
              width: 680,
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

  testWidgets('Manual Reprocess is hidden when every need is off', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      character: CharacterCard(
        name: 'Aria Vale',
        frontPorchExtensions: FrontPorchExtensions(
          needsOff: List<String>.from(NeedsSimulation.needKeys),
        ),
      ),
    );
    expect(find.text('Manual Reprocess'), findsNothing);
  });

  testWidgets('Manual Reprocess is hidden when Needs is off', (tester) async {
    await pumpBubble(
      tester,
      character: CharacterCard(name: 'Aria Vale'),
      needsSimEnabled: false,
    );
    expect(find.text('Manual Reprocess'), findsNothing);
  });

  testWidgets('Manual Reprocess is shown when Needs is on and keys remain', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      character: CharacterCard(
        name: 'Aria Vale',
        frontPorchExtensions: FrontPorchExtensions(needsOff: const ['hygiene']),
      ),
    );
    expect(find.text('Manual Reprocess'), findsOneWidget);
  });
}
