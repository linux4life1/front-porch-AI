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

// UI Settings dialog interaction net — required by the provability rule
// BEFORE ui_settings_dialog.dart is split. The goldens render it but nothing
// TAPS it (theme_interaction_test sets themes programmatically). Pins the
// section landmarks of the future parts and drives the color-picker dialog
// open through a real tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/ui_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sections render and the color picker opens by real tap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1250));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = FakeStorageService();
    final chat = FakeChatService();
    addTearDown(storage.dispose);
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Material(child: UiSettingsDialog())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // One landmark per future part.
    for (final landmark in ['Chat Theme', 'Appearance', 'Chat Colors']) {
      expect(find.textContaining(landmark), findsWidgets,
          reason: '"$landmark" landmark missing — its future part would be '
              'detached');
    }

    // Drive the color picker (its own future part) open via a real tap on
    // the first color row's swatch, then cancel out.
    final label = find.text('AI Bubble');
    await tester.scrollUntilVisible(label.first, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
    // The row's real tap target is its trailing IconButton.
    final rowButton = find.descendant(
      of: find.ancestor(of: label.first, matching: find.byType(Row)).first,
      matching: find.byType(IconButton),
    );
    await tester.tap(rowButton.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel'), findsWidgets,
        reason: 'tapping a color row must open the picker dialog — its '
            'future part would otherwise be detached');
    await tester.tap(find.text('Cancel').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel'), findsNothing,
        reason: 'Cancel must close the picker');
  });
}
