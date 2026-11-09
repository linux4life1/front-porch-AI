// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/prompts_section.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage() {
    generationSettings.initializeBase(null, notifyListeners);
    presetSettings.initializeBase(null, notifyListeners);
  }

  @override
  final GenerationSettings generationSettings = GenerationSettings();
  @override
  final PresetSettings presetSettings = PresetSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('PromptsSection renders category header, badges, and 3 stacked cards', (tester) async {
    final storage = _FakeStorage();
    final controller = TextEditingController(text: 'Hello test prompt');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PromptsSection(systemPromptController: controller),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Default Prompts & Instructions'), findsOneWidget);
    expect(find.text('{{char}}'), findsAtLeastNWidgets(1));
    expect(find.text('{{user}}'), findsAtLeastNWidgets(1));
    expect(find.text('Fallback system prompt'), findsAtLeastNWidgets(1));
    expect(find.text('Group system prompt'), findsAtLeastNWidgets(1));
    expect(find.text('Global prompt additions'), findsOneWidget);
  });
}
