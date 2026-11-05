// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The freeze confirmation on the sidebar Pockets line
// (docs/design/pockets-wardrobe-chat-toggle.md): turning OFF asks first,
// and ONLY Yes flips. Turning on is instant — no dialog, no retro-scan.
// The copy names the member in groups; a dismissed dialog writes nothing.
// Service-side promises (zero model calls, retention, seeds): the sibling
// test/services/chat/pockets_chat_toggle_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, PocketItem;
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/pockets_gate_line.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// The golden fake with a live-switch mind: it answers the STORED switch and
/// records every write, so "Yes wrote / No wrote nothing" is provable.
class _GateChat extends FakeChatService {
  _GateChat({required super.activeCharacter, this.groupMode = false});

  final bool groupMode;
  bool storedSwitch = true;
  final List<bool> oneToOneWrites = [];
  final List<(String, bool)> memberWrites = [];

  @override
  bool get isGroupMode => groupMode;

  @override
  bool get pocketsFeatureEnabled => true;

  @override
  bool pocketsSwitchFor(String memberId) => storedSwitch;

  @override
  Pockets? pocketsFor(String characterId) =>
      storedSwitch ? Pockets(carrying: [const PocketItem('house keys')]) : null;

  @override
  Future<void> setPocketsEnabled(bool on) async {
    oneToOneWrites.add(on);
    flip(on);
  }

  @override
  Future<void> setMemberPocketsEnabled(String memberId, bool on) async {
    memberWrites.add((memberId, on));
    flip(on);
  }

  /// Move the stored switch and repaint, the way a real write notifies.
  void flip(bool v) {
    storedSwitch = v;
    notifyListeners();
  }
}

Future<FakeStorageService> _pump(
  WidgetTester tester,
  ChatService chat, {
  required String characterId,
  required String characterName,
}) async {
  final storage = FakeStorageService();
  // Porch Life defaults Pockets off; this line's whole job presumes the
  // global is on (the veto case is pinned by the widget's greyed note).
  await storage.realismSettings.setPocketsEnabled(true);
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
            // The real sidebar's group watches ChatService and remounts the
            // leaf on notify; without the Consumer a flip here would never
            // repaint and the switch would answer stale.
            child: Consumer<ChatService>(
              builder: (context, svc, _) => PocketsGateLine(
                chat: svc,
                characterId: characterId,
                characterName: characterName,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return storage;
}

Switch switchOf(WidgetTester tester) => tester.widget<Switch>(
  find.descendant(
    of: find.byType(PocketsGateLine),
    matching: find.byType(Switch),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_GateChat> pumpOne(WidgetTester tester) async {
    final chat = _GateChat(
      activeCharacter: CharacterCard(
        name: 'Carmen',
        frontPorchExtensions: FrontPorchExtensions(pocketsEnabled: true),
      ),
    );
    await _pump(tester, chat, characterId: 'carmen', characterName: 'Carmen');
    return chat;
  }

  testWidgets('the line shows the stored switch and no dialog on the row', (
    tester,
  ) async {
    await pumpOne(tester);
    expect(switchOf(tester).value, isTrue);
    expect(find.text('Pockets & Wardrobe'), findsOneWidget);
    expect(find.textContaining('catch-up'), findsNothing);
  });

  testWidgets('tapping off opens the freeze confirmation, wording and all', (
    tester,
  ) async {
    final chat = await pumpOne(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(PocketsGateLine),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Turn off Pockets & Wardrobe for Carmen?'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no catch-up mechanic implemented'),
      findsOneWidget,
      reason: 'the promise the dialog must say aloud',
    );
    expect(
      find.textContaining(
        'Carmen’s current inventory and wardrobe will be retained '
        'but no longer tracked',
      ),
      findsOneWidget,
    );
    expect(find.text('Yes, turn off'), findsOneWidget);
    expect(find.text('No, keep on'), findsOneWidget);
    expect(
      chat.oneToOneWrites,
      isEmpty,
      reason: 'the row alone writes nothing',
    );
  });

  testWidgets('No, keep on: dialog closes, nothing is written, still on', (
    tester,
  ) async {
    final chat = await pumpOne(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(PocketsGateLine),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, keep on'));
    await tester.pumpAndSettle();

    expect(chat.oneToOneWrites, isEmpty);
    expect(chat.storedSwitch, isTrue);
    expect(switchOf(tester).value, isTrue);
  });

  testWidgets('Yes, turn off: the only path that writes false', (tester) async {
    final chat = await pumpOne(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(PocketsGateLine),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, turn off'));
    await tester.pumpAndSettle();

    expect(chat.oneToOneWrites, [false]);
    expect(chat.storedSwitch, isFalse);
  });

  testWidgets('turning back on is instant — no dialog on the way up', (
    tester,
  ) async {
    final chat = await pumpOne(tester);
    chat.flip(false);
    await tester.pump();
    expect(switchOf(tester).value, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(PocketsGateLine),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('catch-up'), findsNothing);
    expect(chat.oneToOneWrites, [true]);
  });

  testWidgets('a group dialog names the member and routes the member setter', (
    tester,
  ) async {
    final chat = _GateChat(
      groupMode: true,
      activeCharacter: CharacterCard(name: 'Ben'),
    );
    await _pump(tester, chat, characterId: 'mem-ben', characterName: 'Ben');

    await tester.tap(
      find.descendant(
        of: find.byType(PocketsGateLine),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn off Pockets & Wardrobe for Ben?'), findsOneWidget);
    expect(
      find.textContaining('Ben’s current inventory'),
      findsOneWidget,
      reason: 'same popup in groups as 1:1, with the member named',
    );
    await tester.tap(find.text('Yes, turn off'));
    await tester.pumpAndSettle();
    expect(chat.memberWrites, [('mem-ben', false)]);
    expect(chat.oneToOneWrites, isEmpty);
  });
}
