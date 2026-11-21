// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/styled_chat_message.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/create_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/widgets/bot_card_type_field.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create, edit and chat with a Bot in the desktop app', (
    tester,
  ) async {
    final temporary = await Directory.systemTemp.createTemp('fpai_native_bot_');
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = SandboxPathProvider(temporary.path);
    final backend = await FakeBackendServer.start(
      replyPieces: ['Start with a silent outline.'],
    );
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'synthetic-bot',
      'realism_default': false,
      'passage_of_time_default': false,
      'journal_enabled': false,
    });
    addTearDown(() async {
      await backend.close();
      PathProviderPlatform.instance = paths;
      await temporary.delete(recursive: true);
    });

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    final context = tester.element(find.byType(MainLayout));
    final navigator = Navigator.of(context);
    final library = context.read<CharacterRepository>();
    final chat = context.read<ChatService>();

    Future<void> press(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 350));
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => const CreateCharacterPage()),
    );
    await pumpUntilFound(tester, find.byType(BotCardTypeField));
    await tester.enterText(find.byType(TextField).first, 'Juniper QA');
    await press(find.byType(DropdownButton<bool>));
    await press(find.text('Bot').last);
    await press(find.text('Next: Personality'));
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Scope'), findsOneWidget);
    expect(find.text('Behavior instructions'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Interview coach');
    await tester.enterText(
      find.byType(TextField).at(2),
      'Practice aloud or in silence.',
    );
    await tester.enterText(find.byType(TextField).at(3), 'Offer one step.');
    await press(find.text('Next: Dialogue'));
    const opener = 'Start with "My name is…" and one detail.';
    await tester.enterText(find.byType(TextField).first, opener);
    for (final next in ['Lorebook', 'Porch Life', 'Review & Create']) {
      await press(find.text('Next: $next'));
    }
    expect(find.text('Card type · Bot'), findsOneWidget);
    await press(find.text('Opening preview'));
    expect(
      tester
          .widget<StyledChatMessage>(find.byType(StyledChatMessage))
          .plainProse,
      isTrue,
    );
    await press(find.widgetWithText(ElevatedButton, 'Create Character'));
    await pumpUntilFound(tester, find.text('Done'));

    final bot = library.characters.singleWhere(
      (card) => card.name == 'Juniper QA',
    );
    expect(bot.behaviorInstructions, 'Offer one step.');
    expect(bot.scenario, 'Practice aloud or in silence.');
    await press(find.text('Done'));
    await chat.setActiveCharacter(bot);
    navigator.push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await pumpUntilFound(
      tester,
      find.textContaining(opener, findRichText: true),
    );
    expect(chat.messages.first.isBotProse, isTrue);
    await chat.sendMessage('I am on a quiet train.');
    expect(chat.messages.last.isBotProse, isTrue);
    await pumpUntilFound(
      tester,
      find.textContaining('Start with a silent outline.', findRichText: true),
    );

    navigator.push(
      MaterialPageRoute(builder: (_) => EditCharacterPage(character: bot)),
    );
    await pumpUntilFound(tester, find.byType(BotCardTypeField));
    expect(
      tester.widget<BotCardTypeField>(find.byType(BotCardTypeField)).bot,
      isTrue,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Offer one step.'),
      'Offer one written prompt.',
    );
    await press(find.text('Save'));
    expect(
      library.characters
          .singleWhere((card) => card.dbId == bot.dbId)
          .behaviorInstructions,
      'Offer one written prompt.',
    );
    expect(chat.sessionGenSettings.soloBot?.instructions, 'Offer one step.');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
