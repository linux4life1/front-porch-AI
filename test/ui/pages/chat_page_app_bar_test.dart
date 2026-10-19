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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/chat_page_sidebar_host.dart';

import '../../golden/support/fakes.dart';

class _OneOnOne extends FakeChatService {
  _OneOnOne(this.card) : super(realismEnabled: false);
  final CharacterCard card;

  @override
  List<ChatParticipant> get cast => [ChatParticipant(card: card, isHost: true)];
}

void main() {
  testWidgets('a 1:1 chat header shows the name without a cut of the '
      'description', (tester) async {
    final chat = _OneOnOne(
      CharacterCard(
        name: 'Mabel',
        description: '{{char}} lives next door to {{user}}.',
      ),
    );
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ChatPageAppBar(
            chatService: chat,
            coverFor: (_, _) => null,
            sidebarOpen: false,
            onToggleSidebar: () {},
          ),
        ),
      ),
    );
    expect(find.text('Mabel'), findsOneWidget);
    expect(find.textContaining('lives next door'), findsNothing);
    expect(find.textContaining('{{'), findsNothing);
  });
}
