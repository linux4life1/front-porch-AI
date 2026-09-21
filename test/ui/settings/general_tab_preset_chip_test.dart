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

// Settings → General → Model Instructions: the built-in preset chips must move
// the VISIBLE text field as well as storage. The controller is owned by the
// settings page, so a notify-driven rebuild never touches its text — a chip
// that only wrote storage left the old prompt on screen, and the field's
// onChanged then saved that stale text straight back over the preset on the
// next keystroke.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage() {
    generationSettings.initializeBase(null, notifyListeners);
    uiSettings.initializeBase(null, notifyListeners);
    presetSettings.initializeBase(null, notifyListeners);
    realismSettings.initializeBase(null, notifyListeners);
    generationSettings.setSystemPrompt('MY OWN PROMPT');
    realismSettings.setAdultThemesEnabled(false);
  }

  @override
  final GenerationSettings generationSettings = GenerationSettings();
  @override
  final UiSettings uiSettings = UiSettings();
  @override
  final PresetSettings presetSettings = PresetSettings();
  @override
  final RealismSettings realismSettings = RealismSettings();

  @override
  String get spellCheckLanguage => kSpellCheckOff;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a preset chip updates the visible prompt field, not just storage',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = _FakeStorage();
      addTearDown(storage.dispose);
      final controller = TextEditingController(
        text: storage.generationSettings.systemPrompt,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: GeneralTab(systemPromptController: controller),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final chip = find.widgetWithText(ActionChip, '🖥️ KoboldCPP');
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      // NOT pumpAndSettle: the spell-check row's spinner is an infinite
      // animation while its platform lookup is pending.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chip);
      await tester.pump();

      expect(
        storage.generationSettings.systemPrompt,
        defaultKoboldSystemPrompt,
      );
      // The field the user is looking at — the half that was missing.
      expect(controller.text, defaultKoboldSystemPrompt);

      // And the next keystroke can no longer resurrect the old prompt: the
      // field's onChanged now carries the preset, not the stale text.
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.controller == controller,
      );
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(field, '${controller.text} extra');
      await tester.pump();
      expect(
        storage.generationSettings.systemPrompt,
        '$defaultKoboldSystemPrompt extra',
      );
    },
  );
}
