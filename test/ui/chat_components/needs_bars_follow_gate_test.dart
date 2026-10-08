// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Needs bars show while Needs run, and only then. Needs run behind one
// gate (Realism AND this chat's Needs switch AND Porch Life Needs); with
// any of them off nothing moves the bars, and the sidebar kept drawing
// them frozen, which read as "Needs are still on" (maintainer, 2026-10-08:
// "Needs bars shouldn't be visible with needs off"). Realism stays on
// with Needs off: bond and trust keep showing, the bars go.
// The phone's feed and the Porch Life switch: test/services/web/
// needs_bars_feed_gate_test.dart, on a real chat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

FakeChatService _chat({required bool realism, required bool needs}) {
  final chat = FakeChatService(
    realismEnabled: realism,
    needsSimEnabled: needs,
    activeCharacter: CharacterCard(
      name: 'Carmen',
      frontPorchExtensions: FrontPorchExtensions(needsSimEnabled: true),
    ),
  );
  // Hide is not erase: the vector stays whatever the switches say.
  chat.needsSimulation.restoreFromSnapshot({
    'vector': {
      'hunger': 80,
      'bladder': 80,
      'energy': 80,
      'social': 80,
      'fun': 80,
      'hygiene': 80,
      'comfort': 80,
    },
  });
  return chat;
}

Future<void> _pumpSidebar(WidgetTester tester, FakeChatService chat) async {
  final storage = FakeStorageService();
  addTearDown(chat.dispose);
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<ChatService>.value(value: chat),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: CharacterStateGroup(
                chat: chat,
                isGroup: false,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cases = [
    (realism: true, needs: true, shows: true, label: 'Realism on, Needs on'),
    (realism: true, needs: false, shows: false, label: 'Realism on, Needs off'),
    (realism: false, needs: true, shows: false, label: 'Realism off, Needs on'),
  ];

  for (final c in cases) {
    testWidgets('sidebar: ${c.label} → bars ${c.shows ? 'show' : 'hidden'}', (
      tester,
    ) async {
      final chat = _chat(realism: c.realism, needs: c.needs);
      await _pumpSidebar(tester, chat);
      expect(chat.needsSimulation.vector, isNotEmpty);
      expect(
        find.byType(NeedsGrid),
        c.shows ? findsOneWidget : findsNothing,
        reason: 'the bars answer the Needs gate, not the stored switch',
      );
    });
  }
}
