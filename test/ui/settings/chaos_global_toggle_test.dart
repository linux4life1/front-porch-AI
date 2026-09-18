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

// Chaos Mode's global default (maintainer, 2026-08-08: "Chaos mode should have
// a global toggle in Porch life with no hard dep, then you can get rid of that
// annoying ChAoS mOde Is SeT pEr ChAt message at the bottom").
//
// Chaos was the last feature Porch Life had to APOLOGISE for: a paragraph at
// the foot of the tab explaining that one switch lived somewhere else. It had
// no global setting at all — the only way to start a chat with Chaos on was to
// author it onto the card or flip it per chat, every chat, forever.
//
// It depends on nothing, and that is a finding rather than an assumption: the
// 2026-08-07 audit (docs/design/feature-independence.md) established that Chaos
// runs fully with the Realism Engine off and had only ever been FILED beside
// it. So the row carries the "works alone" chip and no gate.
//
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Real [RealismSettings] behind the storage fake, so the switch under test
/// drives production code. Same shim as after_dark_group_test.
class _ChaosStorage extends FakeStorageService {
  _ChaosStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_ChaosStorage> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _ChaosStorage();
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
    return storage;
  }

  testWidgets('Chaos Mode is a row on the tab and it works alone', (
    tester,
  ) async {
    final storage = await pump(tester);
    final scrollable = find.byType(Scrollable).first;

    final row = find.text('Chaos Mode');
    await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
    expect(
      row,
      findsOneWidget,
      reason:
          'the maintainer asked for a global toggle in Porch Life; before '
          'this there was none anywhere in Settings',
    );

    // The switch immediately after the label, found through the row's own
    // subtree so a neighbouring row cannot answer for it.
    final sw = find.descendant(
      of: find.ancestor(of: row, matching: find.byType(Row)).last,
      matching: find.byType(Switch),
    );
    expect(sw, findsOneWidget);
    expect(
      tester.widget<Switch>(sw).onChanged,
      isNotNull,
      reason:
          'no hard dependency — the audit found Chaos runs with the '
          'Realism Engine off, so this switch must never be gated',
    );

    expect(
      storage.realismSettings.chaosModeDefault,
      isFalse,
      reason:
          'Chaos injects unplanned events into a story; that is nobody\'s '
          'default',
    );
    await tester.ensureVisible(sw);
    await tester.pump();
    await tester.tap(sw);
    await tester.pump(const Duration(milliseconds: 300));
    expect(storage.realismSettings.chaosModeDefault, isTrue);
  });

  testWidgets('the tab no longer apologises for Chaos living elsewhere', (
    tester,
  ) async {
    await pump(tester);
    final scrollable = find.byType(Scrollable).first;

    // Scroll to the end so the closing card is definitely built.
    await tester.drag(scrollable, const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('set per chat rather than globally'),
      findsNothing,
      reason:
          'that sentence was only true while Chaos had no global switch; '
          'leaving it up would now be actively wrong',
    );
    expect(
      find.textContaining('These are the defaults new chats start from'),
      findsOneWidget,
      reason:
          'the replacement states the relationship the right way round — '
          'globals here, per-chat override in the sidebar',
    );
  });
}
