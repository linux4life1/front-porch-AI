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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/dialogs/reprocess_needs_dialog.dart';

import '../../golden/support/fakes.dart';

ChatMessage _stamped() => ChatMessage(
  text: '"Evening," she said.',
  sender: 'Aria',
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

Future<void> _pump(
  WidgetTester tester, {
  required CharacterCard character,
  bool needsSimEnabled = true,
  Future<void> Function(String, Set<String>)? onSubmit,
}) async {
  final chat = FakeChatService(
    activeCharacter: character,
    messages: [_stamped()],
    needsSimEnabled: needsSimEnabled,
  );
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ChatService>.value(
      value: chat,
      child: MaterialApp(
        home: Scaffold(
          body: ReprocessNeedsDialog(
            index: 0,
            onSubmit: onSubmit ?? (_, _) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('two needs off shows five chips and hides the off ones', (
    tester,
  ) async {
    await _pump(
      tester,
      character: CharacterCard(
        name: 'Aria',
        frontPorchExtensions: FrontPorchExtensions(
          needsOff: const ['hygiene', 'fun'],
        ),
      ),
    );

    expect(find.byType(FilterChip), findsNWidgets(5));
    expect(find.text('Hunger'), findsOneWidget);
    expect(find.text('Comfort'), findsOneWidget);
    expect(find.text('Hygiene'), findsNothing);
    expect(find.text('Fun'), findsNothing);
    expect(find.text(kReprocessNeedsEmptyHelper), findsOneWidget);
  });

  testWidgets('one enabled hides the scope block and submits empty scope', (
    tester,
  ) async {
    Set<String>? scope;
    await _pump(
      tester,
      character: CharacterCard(
        name: 'Aria',
        frontPorchExtensions: FrontPorchExtensions(
          needsOff: NeedsSimulation.needKeys
              .where((k) => k != 'hunger')
              .toList(),
        ),
      ),
      onSubmit: (critique, onlyNeeds) async {
        expect(critique, 'they ate');
        scope = onlyNeeds;
      },
    );

    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Limit to these needs'), findsNothing);
    expect(
      find.text(reprocessNeedsOneEnabledLine('hunger', 'Aria')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'they ate');
    await tester.tap(find.text('Reprocess'));
    await tester.pumpAndSettle();
    expect(scope, isEmpty);
  });

  testWidgets('resolver null shows the nothing line and Close only', (
    tester,
  ) async {
    await _pump(
      tester,
      character: CharacterCard(
        name: 'Aria',
        frontPorchExtensions: FrontPorchExtensions(
          needsOff: List<String>.from(NeedsSimulation.needKeys),
        ),
      ),
    );

    expect(find.text(kReprocessNeedsNothing), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Reprocess'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('empty helper string is exact', (tester) async {
    await _pump(
      tester,
      character: CharacterCard(
        name: 'Aria',
        frontPorchExtensions: FrontPorchExtensions(needsOff: const ['hygiene']),
      ),
    );
    expect(
      find.text('Nothing selected — every need shown here is re-evaluated.'),
      findsOneWidget,
    );
  });
}
