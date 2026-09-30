// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life Passage of Time is the only live clock gate. Chat settings
// must not offer a second switch. A real ChatService cannot be driven
// under testWidgets (Drift hangs). Send/regen gates live in
// one_to_one_clock_wear_chip_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chat-settings has no Passage of Time toggle', (tester) async {
    final storage = FakeStorageService();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CharacterStateSettings(chat: chat, isGroup: false),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Automatic Passage of Time'), findsNothing);
    expect(find.text('Passage of Time'), findsNothing);
  });

  testWidgets('Porch Life Passage of Time exists and is the live gate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = FakeStorageService();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    expect(storage.realismSettings.passageOfTimeDefault, isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Passage of Time'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('Passage of Time'), findsOneWidget);
    expect(find.textContaining('every open chat'), findsWidgets);

    final potRow = find.ancestor(
      of: find.text('Passage of Time'),
      matching: find.byType(FeatureRow),
    );
    expect(potRow, findsOneWidget);
    await tester.tap(
      find.descendant(of: potRow, matching: find.byType(Switch)),
    );
    await tester.pump();
    expect(storage.realismSettings.passageOfTimeDefault, isFalse);
  });
}
