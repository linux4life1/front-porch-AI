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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

void main() {
  setupPathProviderMock();

  Future<void> pumpBanner(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final msg = ChatMessage(
      text: '[🎰 CHANCE TIME! A raccoon steals the pie]',
      sender: 'System',
      isUser: false,
      metadata: const {'is_chance_time_narration': true},
    );
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
            child: MessageBubble(message: msg, index: 0, chatService: chat),
          ),
        ),
      ),
    );
  }

  testWidgets('banner sentence is selectable', (tester) async {
    await pumpBanner(tester);
    expect(find.textContaining('A raccoon steals the pie'), findsOneWidget);
    final el = tester.element(find.textContaining('A raccoon steals the pie'));
    expect(el.findAncestorWidgetOfExactType<SelectionArea>(), isNotNull);
  });

  testWidgets('banner long-press still offers delete', (tester) async {
    await pumpBanner(tester);
    await tester.longPress(find.textContaining('A raccoon steals the pie'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Message'), findsOneWidget);
  });
}
