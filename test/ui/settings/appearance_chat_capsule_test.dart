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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/services/storage/settings/ui_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/appearance_tab.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/chat_appearance_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/chat_capsule_preview.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/chat_color_matrix.dart';

class _Storage extends ChangeNotifier implements StorageService {
  _Storage() {
    appearance.initializeBase(null, notifyListeners);
    appearance.load();
    uiSettings = UiSettings(appearance)..initializeBase(null, notifyListeners);
    uiSettings.load();
    realismSettings.initializeBase(null, notifyListeners);
    realismSettings.load();
  }

  @override
  final AppearanceSettings appearance = AppearanceSettings();

  @override
  late final UiSettings uiSettings;

  @override
  final RealismSettings realismSettings = RealismSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Storage> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 800,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = _Storage();
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<StorageService>.value(
      value: storage,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
  return storage;
}

void main() {
  testWidgets('ChatCapsulePreview renders two-turn exchange with real renderer', (
    tester,
  ) async {
    bool aiTapped = false;
    bool userTapped = false;

    await _pump(
      tester,
      ChatCapsulePreview(
        onTapAiBubble: () => aiTapped = true,
        onTapUserBubble: () => userTapped = true,
      ),
    );

    expect(find.text('LIVE PREVIEW'), findsOneWidget);
    expect(find.text('Perfect. Let\'s get to work.'), findsOneWidget);
    expect(find.textContaining('I found the notes'), findsOneWidget);
    expect(find.textContaining('she smiles'), findsOneWidget);

    // Verify taps trigger callbacks
    await tester.tap(find.textContaining('she smiles'));
    expect(aiTapped, isTrue);

    await tester.tap(find.text('Perfect. Let\'s get to work.'));
    expect(userTapped, isTrue);
  });

  testWidgets('ChatColorMatrix displays color chips without contrast badges', (
    tester,
  ) async {
    await _pump(tester, const ChatColorMatrix());

    expect(find.text('USER MESSAGE'), findsOneWidget);
    expect(find.text('CHARACTER MESSAGE'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-color-user-bubble')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-color-user-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-color-ai-bubble')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-color-ai-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-color-dialogue')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-color-action')), findsOneWidget);

    // Confirm contrast badges are completely removed
    expect(find.textContaining(':1 AA'), findsNothing);
    expect(find.textContaining(':1 Low'), findsNothing);
  });

  testWidgets('tapping color chips in ChatColorMatrix opens color picker dialog', (
    tester,
  ) async {
    await _pump(tester, const ChatColorMatrix());

    await tester.tap(find.byKey(const ValueKey('chat-color-user-bubble')));
    await tester.pumpAndSettle();

    expect(find.text('Select Color'), findsOneWidget);
  });

  testWidgets('ChatAppearanceSection renders cleanly at 360px without overflow', (
    tester,
  ) async {
    await _pump(tester, const ChatAppearanceSection(), width: 360);

    expect(tester.takeException(), isNull);
    expect(find.text('Chat Appearance'), findsOneWidget);
    expect(find.text('Reading Size'), findsOneWidget);
    expect(find.text('Chat Font'), findsOneWidget);
    expect(find.byType(ChatCapsulePreview), findsOneWidget);
    expect(find.byType(ChatColorMatrix), findsOneWidget);
  });

  testWidgets('AppearanceTab renders cleanly at 360px without overflow', (
    tester,
  ) async {
    await _pump(tester, const AppearanceTab(), width: 360);

    expect(tester.takeException(), isNull);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Chat Appearance'), findsOneWidget);
  });

  testWidgets('ChatAppearanceSection wires preview bubble taps to color picker', (
    tester,
  ) async {
    await _pump(tester, const ChatAppearanceSection());

    await tester.tap(find.text('Perfect. Let\'s get to work.'));
    await tester.pumpAndSettle();

    expect(find.text('Select Color'), findsOneWidget);
  });
}
