// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
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
  testWidgets(
    'PromptsSection renders category header, badges, and 3 stacked cards',
    (tester) async {
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
    },
  );

  testWidgets(
    'GlobalPromptAdditions macro chips smart-append when unfocused and insert at caret when focused',
    (tester) async {
      final storage = _FakeStorage();
      await storage.generationSettings.setAdditionalSystemPrompt('Be concise');
      await storage.generationSettings.setAdditionalPostHistoryInstructions(
        'Speak to  kindly',
      );
      final controller = TextEditingController(text: 'Hello');
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

      // Unfocused smart-append on Additional system instructions
      final sysChar = find.byKey(const ValueKey('sys-additions-macro-char'));
      await tester.ensureVisible(sysChar);
      await tester.pump();
      await tester.tap(sysChar);
      await tester.pump();
      expect(
        storage.generationSettings.additionalSystemPrompt,
        'Be concise {{char}}',
      );

      // Focus post-history field at caret position 9 ("Speak to | kindly")
      final postFieldFinder = find.widgetWithText(
        TextFormField,
        'Additional post-history instructions',
      );
      await tester.ensureVisible(postFieldFinder);
      await tester.pump();
      await tester.tap(postFieldFinder);
      await tester.pump();
      final editableState = tester.state<EditableTextState>(
        find.descendant(
          of: postFieldFinder,
          matching: find.byType(EditableText),
        ),
      );
      editableState.userUpdateTextEditingValue(
        const TextEditingValue(
          text: 'Speak to  kindly',
          selection: TextSelection.collapsed(offset: 9),
        ),
        SelectionChangedCause.tap,
      );
      await tester.pump();

      final postUser = find.byKey(const ValueKey('post-additions-macro-user'));
      await tester.ensureVisible(postUser);
      await tester.pump();
      await tester.tap(postUser);
      await tester.pump();
      expect(
        storage.generationSettings.additionalPostHistoryInstructions,
        'Speak to {{user}} kindly',
      );
    },
  );
}
