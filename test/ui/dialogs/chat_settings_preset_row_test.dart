// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Chat Settings' "Preset for this chat" (issue 686): picking a preset copies
// it into the chat's own values and saves them; "Follow the model" clears
// them; a field's ↺ drops just that field back to the global value; and the
// chat's values can be saved as a new preset. The dialog is the same for a
// 1:1 and a group chat (both edit ChatService.sessionGenSettings).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/chat_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/double_tap.dart';
import '../gen_preset_storage.dart';

/// Keeps what the dialog saves, as the real ChatService does.
class _SavingChat extends FakeChatService {
  ChatGenerationSettings gen = ChatGenerationSettings(
    bannedPhrases: const <String>[],
  );
  int writes = 0;

  @override
  ChatGenerationSettings get sessionGenSettings => gen;
  @override
  set sessionGenSettings(ChatGenerationSettings value) {
    writes++;
    gen = value;
  }
}

Future<(GenPresetStorage, _SavingChat)> _mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = await GenPresetStorage.create();
  await storage.generationSettings.setTemperature(0.7);
  await storage.genPresets.savePreset(
    'Crisp',
    const SamplerValues(temperature: 0.3, minP: 0.2, maxLength: 700),
  );
  final chat = _SavingChat();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<LLMProvider>.value(value: FakeLLMProvider()),
        ChangeNotifierProvider<ChatService>.value(value: chat),
      ],
      child: const MaterialApp(home: ChatSettingsDialog()),
    ),
  );
  await tester.pump();
  return (storage, chat);
}

/// Opens the row's picker, now showing [from] ('' = Follow the model), and
/// picks [to].
Future<void> _choose(WidgetTester tester, String from, String to) async {
  await tester.tap(find.byKey(ValueKey('chat-gen-preset-$from')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(to).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a preset loads into the chat\'s own values and Follow the '
      'model clears them', (tester) async {
    final (storage, chat) = await _mount(tester);
    expect(find.text('Following the model'), findsOneWidget);

    await _choose(tester, '', 'Crisp');
    expect(chat.gen.temperature, 0.3);
    expect(chat.gen.minP, 0.2);
    expect(chat.gen.maxLength, 700);
    expect(chat.gen.genPresetName, 'Crisp');
    expect(storage.generationSettings.temperature, 0.7);

    await _choose(tester, 'Crisp', 'Follow the model');
    expect(chat.gen.temperature, isNull);
    expect(chat.gen.genPresetName, isNull);
    expect(chat.gen.hasOverrides, isTrue, reason: 'banned phrases kept');
  });

  testWidgets('a field\'s ↺ drops only that field back to the global value', (
    tester,
  ) async {
    final (_, chat) = await _mount(tester);
    expect(find.byTooltip('Use the global value'), findsNothing);

    await _choose(tester, '', 'Crisp');
    // Temperature, Min-P and Max Output Tokens are the chat's own now.
    expect(find.byTooltip('Use the global value'), findsNWidgets(3));

    await tester.tap(find.byTooltip('Use the global value').first);
    await tester.pumpAndSettle();
    expect(chat.gen.temperature, isNull);
    expect(chat.gen.minP, 0.2);
    expect(find.byTooltip('Use the global value'), findsNWidgets(2));
    expect(find.text('Crisp (edited)'), findsOneWidget);
  });

  testWidgets('the chat\'s values save as one new preset', (tester) async {
    final (storage, chat) = await _mount(tester);
    await _choose(tester, '', 'Crisp');
    final before = storage.genPresets.saves;

    await tester.ensureVisible(
      find.text('Save this chat’s values as a preset…'),
    );
    await doubleTapNoFrame(
      tester,
      find.text('Save this chat’s values as a preset…'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('gen-preset-name')),
      'Crisp chat',
    );
    await doubleTapNoFrame(tester, find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(storage.genPresets.saves - before, 1);
    final saved = storage.genPresets.presets['Crisp chat']!;
    expect(saved.temperature, 0.3);
    expect(saved.topP, storage.generationSettings.topP);
    expect(chat.gen.genPresetName, 'Crisp chat');
  });
}
