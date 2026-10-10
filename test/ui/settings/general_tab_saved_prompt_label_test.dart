// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → Model Instructions: after picking a saved prompt and
// then pressing the "Group Chat" preset button, the box held the group
// prompt but the saved-prompt dropdown still named the old pick. The
// dropdown now names the saved prompt whose text is in the box, or none.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab.dart';

const _saved = 'Immersive Roleplay';
const _savedText = 'You are {{char}}. Stay in character.';

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage() {
    generationSettings.initializeBase(null, notifyListeners);
    uiSettings.initializeBase(null, notifyListeners);
    presetSettings.initializeBase(null, notifyListeners);
    realismSettings.initializeBase(null, notifyListeners);
    generationSettings.setSystemPrompt('MY OWN PROMPT');
    presetSettings.savePrompt(_saved, _savedText);
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

/// The value the saved-prompt dropdown shows.
String? _shown(WidgetTester tester) => tester
    .state<FormFieldState<String>>(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
    )
    .value;

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  // NOT pumpAndSettle: the spell-check row's spinner never settles.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.last);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a preset button clears the stale saved-prompt name', (
    tester,
  ) async {
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
          home: Scaffold(body: GeneralTab(systemPromptController: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester), isNull);

    await _tapVisible(tester, find.text('Load saved prompt...'));
    await _tapVisible(tester, find.text(_saved));
    expect(controller.text, _savedText);
    expect(_shown(tester), _saved);

    await _tapVisible(tester, find.widgetWithText(ActionChip, '👥 Group Chat'));
    expect(controller.text, defaultGroupSystemPrompt);
    expect(_shown(tester), isNull, reason: 'the old pick\'s name stayed');
    expect(find.text('Load saved prompt...'), findsOneWidget);
  });
}
