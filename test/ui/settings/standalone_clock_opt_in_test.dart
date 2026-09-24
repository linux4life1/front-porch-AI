// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Passage of Time is the single clock driver. The Porch Life row is the
// default for new chats; the leftover standalone sub-switch is gone. The
// standaloneClockEnabled pref is still readable for old PWAs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _ClockStorage extends FakeStorageService {
  _ClockStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kRetiredSubLabel = 'Keep the clock running without the engine';

  Future<(_ClockStorage, FakeChatService)> pumpTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _ClockStorage();
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
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return (storage, chat);
  }

  testWidgets(
    'Porch Life Passage of Time is the new-chat default; standalone switch is gone',
    (tester) async {
      final (storage, _) = await pumpTab(tester);

      expect(storage.realismSettings.passageOfTimeDefault, isTrue);
      expect(
        storage.realismSettings.standaloneClockEnabled,
        isFalse,
        reason: 'leftover pref stays off and is no longer a gate',
      );

      final scrollable = find.byType(Scrollable).first;
      final timeRow = find.text('Passage of Time');
      await tester.scrollUntilVisible(timeRow, 300, scrollable: scrollable);
      expect(timeRow, findsOneWidget);
      expect(
        find.textContaining('default for new chats'),
        findsOneWidget,
        reason: 'the row must say it seeds new chats, not live chat-gear',
      );
      expect(
        find.textContaining('Automatic Passage of Time'),
        findsOneWidget,
        reason: 'the live switch lives on chat-gear',
      );
      expect(
        find.text(kRetiredSubLabel),
        findsNothing,
        reason: 'the standalone sub-switch is collapsed',
      );
    },
  );
}
