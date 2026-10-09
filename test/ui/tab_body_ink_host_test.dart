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

// The Settings page's twins: tabbed views whose tab bar is see-through and
// sits on the same Material as the tab bodies. Ink in a tab body (a focused
// row's grey box) is painted on the nearest Material and clipped only to its
// bounds, so that Material must stop at the tab body or a focused row
// scrolled up shows its box through the tab bar. The Settings page itself is
// pinned by painting in test/ui/settings/settings_tab_focus_ink_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_review.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/dialogs/journal_dialog.dart';
import 'package:front_porch_ai/ui/pages/model_manager_page.dart';

import '../golden/support/creator_test_support.dart';
import '../golden/support/fakes.dart';
import '../golden/support/fakes_services.dart';
import '../golden/support/fakes_storage.dart';

class _JournalChat extends FakeChatService {
  _JournalChat({required this.store}) {
    journalReview = JournalReview(
      store: store,
      getSessionId: () => 's1',
      setRecap: (_) {},
      setCursor: (_) {},
      onSaveChat: () async {},
      onNotify: () {},
      getMaxCards: () => 200,
    );
  }

  final JournalStore store;

  @override
  late final JournalReview journalReview;

  @override
  JournalStore get journalStore => store;

  @override
  String? get currentSessionId => 's1';
}

/// Where the tab bodies' ink may land, against where the tab bar is.
void expectTabInkStaysInBody(WidgetTester tester) {
  final body = find
      .descendant(
        of: find.byType(TabBarView),
        matching: find.byType(Scrollable),
      )
      .first;
  final host = Material.of(tester.element(body)) as RenderBox;
  final inkClip = host.localToGlobal(Offset.zero) & host.size;
  final tabBar = tester.getRect(find.byType(TabBar));
  expect(
    inkClip.overlaps(tabBar),
    isFalse,
    reason:
        'tab bodies paint their ink on a Material that also covers the tab '
        'bar ($inkClip vs tab bar $tabBar)',
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('Model Manager tabs keep their ink off the tab bar', (
    tester,
  ) async {
    final modelManager = FakeModelManager();
    final hardware = FakeHardwareService();
    final storage = FakeStorageService();
    addTearDown(() {
      modelManager.dispose();
      hardware.dispose();
      storage.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelManager>.value(value: modelManager),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<StorageService>.value(value: storage),
        ],
        child: const MaterialApp(home: ModelManagerPage()),
      ),
    );
    await tester.pump();
    expectTabInkStaysInBody(tester);
  });

  testWidgets('Journal tabs keep their ink off the tab bar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(sameIsolate: true);
    final store = JournalStore(getDb: () => db);
    final storage = StorageService();
    final persona = UserPersonaService(db);
    final chat = _JournalChat(store: store);
    addTearDown(() async {
      chat.dispose();
      await db.close();
    });
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<UserPersonaService>.value(value: persona),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: JournalDialog(
                  chatService: chat,
                  ownerId: 'mara',
                  ownerName: 'Mara',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
    expectTabInkStaysInBody(tester);
  });
}
