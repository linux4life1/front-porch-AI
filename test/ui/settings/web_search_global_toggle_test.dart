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

// Web Search's global default (Porch Life) + the four seed sites. Same
// shape as chaos_global_toggle_test: miss a site and the switch is silently
// 1:1-only. Default OFF.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _SearchStorage extends FakeStorageService {
  _SearchStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_SearchStorage> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _SearchStorage();
    storage.webSearchSettings.initializeBase(null, storage.notifyListeners);
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

  testWidgets('Web Search is a row on Porch Life and defaults off', (
    tester,
  ) async {
    final storage = await pump(tester);
    final scrollable = find.byType(Scrollable).first;

    final row = find.text('Web Search');
    await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
    expect(row, findsOneWidget);

    final sw = find.descendant(
      of: find.ancestor(of: row, matching: find.byType(Row)).last,
      matching: find.byType(Switch),
    );
    expect(sw, findsOneWidget);
    expect(
      storage.webSearchSettings.webSearchDefault,
      isFalse,
      reason: 'a per-turn remote lookup is nobody\'s default',
    );
    await tester.ensureVisible(sw);
    await tester.pump();
    await tester.tap(sw);
    await tester.pump(const Duration(milliseconds: 300));
    expect(storage.webSearchSettings.webSearchDefault, isTrue);
  });
}
