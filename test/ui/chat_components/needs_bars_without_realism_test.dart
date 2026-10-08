// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Mac: brand-new 1:1, Needs toggle ON, flip off→on, still no bars.
// Needs bars sat inside the Realism header gate, so a chat that only
// turned Needs on (Porch Life Realism default is off) drew an empty
// strip. Web already keys Needs on needsEnabled, but hid them in the
// same realism-off paragraph. Bars answer to the Needs switch.
// Proven red: CharacterStateGroup with realismEnabled false and a
// filled vector painted no NeedsGrid.
//
// Flipped 2026-10-08. Needs require the Realism engine (the maintainer's
// rule, restated that day: "Needs need Realism"), so with Realism off no
// Needs run and nothing moves the bars. Drawn anyway they sat frozen and
// read as "Needs are still on"; the maintainer ruled they hide ("Needs
// bars shouldn't be visible with needs off"). The bars now follow the
// Needs gate; the full set of cases is needs_bars_follow_gate_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_group.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1:1 Needs bars hide when Realism is off even if Needs is on', (
    tester,
  ) async {
    final chat = FakeChatService(
      realismEnabled: false,
      needsSimEnabled: true,
      activeCharacter: CharacterCard(
        name: 'Carmen',
        frontPorchExtensions: FrontPorchExtensions(needsSimEnabled: true),
      ),
    );
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
            body: SizedBox(
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
    );
    await tester.pump();

    expect(chat.needsSimEnabled, isTrue);
    expect(chat.needsSimulation.vector, isNotEmpty);
    expect(chat.realismEnabled, isFalse);
    expect(
      find.byType(NeedsGrid),
      findsNothing,
      reason:
          'Needs need Realism: with it off no Needs run, so the bars '
          'would only sit frozen and read as live',
    );
  });
}
