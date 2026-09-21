// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life switches are defaults for *new* chats. Flipping Needs off
// while a 1:1 is open must not call ChatService.setNeedsSimEnabled (that
// path saves needsVector: null and reload clears lived-in meters).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _PorchLifeStorage extends FakeStorageService {
  _PorchLifeStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Porch Life Needs flips the default without a live ChatService write',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = _PorchLifeStorage();
      final chat = FakeChatService(needsSimEnabled: true);
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
      await tester.pump();

      Finder rowFor(String label) =>
          find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      final scrollable = find.byType(Scrollable).first;

      Future<void> tapRow(String label) async {
        final labelFinder = find.text(label);
        await tester.scrollUntilVisible(
          labelFinder,
          300,
          scrollable: scrollable,
        );
        final sw = find.descendant(
          of: rowFor(label),
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(sw);
        await tester.pump();
        await tester.tap(sw);
        await tester.pump();
      }

      expect(storage.realismSettings.realismDefault, isFalse);
      expect(storage.realismSettings.needsSimDefault, isTrue);
      expect(chat.needsSimEnabled, isTrue);

      await tapRow('Realism Engine');
      expect(storage.realismSettings.realismDefault, isTrue);
      expect(chat.realismEnabled, isTrue, reason: 'fake is unchanged');

      await tapRow('Needs');
      expect(storage.realismSettings.needsSimDefault, isFalse);
      expect(
        chat.needsSimEnabled,
        isTrue,
        reason: 'the open chat must keep its own switch and meters',
      );
    },
  );
}
