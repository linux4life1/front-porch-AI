// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/web/facade/character/character_card_edits.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

import '../../../integration_test/support/e2e_sandbox.dart';
import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Bot replaces the stock role and retains explicit prompt sources',
    () async {
      final (chat, storage, _) = await openIsolatedChat();
      final card = CharacterCard(name: 'Track Coach');
      final source = chat.promptAssembler.source;
      expect(
        storage.generationSettings.systemPrompt,
        GenerationSettings.defaultSystemPrompt,
      );
      expect(
        source.resolveOneToOneBase(card),
        GenerationSettings.defaultSystemPrompt,
      );
      expect(source.resolveOneToOneBase(card, bot: true), isEmpty);

      await storage.generationSettings.setSystemPrompt('User voice.');
      expect(source.resolveOneToOneBase(card, bot: true), 'User voice.');
      card.systemPrompt = 'Card voice.';
      expect(source.resolveOneToOneBase(card, bot: true), 'Card voice.');
      chat.sessionGenSettings.systemPromptSource = 'user';
      expect(source.resolveOneToOneBase(card, bot: true), 'User voice.');
    },
  );

  test(
    'Selecting a Bot opening preserves prose through session reload',
    () async {
      final (chat, _, library) = await openIsolatedChat();
      final card = CharacterCard(
        name: 'Track Coach',
        firstMessage: 'What shall we practice?',
        alternateGreetings: ['Keeper: “Last train.” *The bell rings.*'],
        frontPorchExtensions: FrontPorchExtensions(
          characterEmotion: 'warm',
          greetingSeeds: const [
            GreetingRealismSeed(characterEmotion: 'furious'),
          ],
        ),
      )..setBotCard(true, 'Ask which topic needs practice.');
      await library.addCharacter(card);
      await chat.setActiveCharacter(card);
      final original = chat.currentSessionId!;
      expect(chat.messages.first.isBotProse, isTrue);

      await chat.selectGreeting(1);
      expect(chat.messages.first.isBotProse, isTrue);

      await chat.startNewChat();
      await chat.loadSession(original);
      final opening = chat.messages.first;
      expect(opening.isBotProse, isTrue);

      expect(opening.displayText, card.alternateGreetings.single);
      expect(opening.toPromptHistoryLine(), startsWith('Track Coach: Keeper:'));
    },
  );

  test('Card keeps full rules while the session keeps a bounded snapshot', () {
    final rule = '🧭' * 2000 + 'Ask one question.';
    final card = CharacterCard(name: 'Track Coach')..setBotCard(true, rule);
    expect(card.behaviorInstructions, rule);
    expect(BotCardSnapshot.fromCard(card)!.instructions, '🧭' * 2000);
  });

  test('Old Bot rules survive a saved card edit and a new chat', () async {
    final (chat, _, library) = await openIsolatedChat();
    const firstRules = 'Use written feedback.';
    const nextRules = 'Use silent practice.';
    final card = CharacterCard(
      name: 'Track Coach',
      firstMessage: 'What shall we practice?',
    )..setBotCard(true, firstRules);
    await library.addCharacter(card);
    await chat.setActiveCharacter(card);
    final original = chat.currentSessionId!;
    expect(chat.sessionGenSettings.soloBot?.instructions, firstRules);

    card.setBotCard(true, nextRules);
    await library.updateCharacter(card);
    await chat.startNewChat();
    expect(chat.currentSessionId, isNot(original));
    expect(chat.sessionGenSettings.soloBot?.instructions, nextRules);
    await chat.loadSession(original);
    expect(chat.sessionGenSettings.soloBot?.instructions, firstRules);
    expect(chat.messages.first.isBotProse, isTrue);
  });

  test(
    'web create, portable JSON and opaque-mode edits preserve card data',
    () {
      final card = newCharacterFromFields({
        'name': 'Track Coach',
        'cardType': 'bot',
        'description': 'Interview coach',
        'scenario': 'Practice introductions',
        'behaviorInstructions': 'Offer one prompt.',
      })!;
      expect(card.cardTypeLabel, 'bot');
      expect(card.behaviorInstructions, 'Offer one prompt.');
      final data = card.toJson();
      expect(data['scenario'], 'Practice introductions');
      expect(data['extensions'][botCardExtension]['kind'], 'bot');

      const opaque = {
        'version': 2,
        'kind': 'bot',
        'example': ['keep'],
      };
      card.rawExtensions = {botCardExtension: opaque, 'unrelated': true};
      applyCharacterFields(card, {
        'cardType': 'character',
        'name': 'New name',
      }, needsSimDefault: false);
      expect(card.name, 'New name');
      expect(card.cardTypeLabel, 'unsupported');
      expect(card.rawExtensions, {botCardExtension: opaque, 'unrelated': true});
    },
  );

  test('a full chat package retains its captured Bot and opening', () async {
    final (chat, _, library) = await openIsolatedChat();
    final card = CharacterCard(
      name: 'Track Coach',
      scenario: 'Practice silently.',
      firstMessage: 'Write your opening sentence.',
    )..setBotCard(true, 'Offer one prompt.');
    await library.addCharacter(card);
    await chat.setActiveCharacter(card);
    final package = (await chat.chatPackager.exportToFpchat())!;

    card.scenario = 'Practice out loud.';
    await library.updateCharacter(card);
    await chat.startNewChat();
    expect(chat.sessionGenSettings.soloBot?.scope, 'Practice out loud.');
    expect(
      (await chat.chatImporter.importChatPackage(package)).fullRestore,
      isTrue,
    );
    expect(chat.sessionGenSettings.soloBot?.scope, 'Practice silently.');
    expect(chat.messages.first.isBotProse, isTrue);
    await chat.estimateContextBudgetNow();
    final estimate = chat.lastPromptSections.values.join('\n');
    expect('Practice silently.'.allMatches(estimate), hasLength(1));
    expect(estimate, isNot(contains('Practice out loud.')));
  });

  test(
    'old Character session stays Character after the library is converted',
    () async {
      final (chat, _, library) = await openIsolatedChat();
      final card = CharacterCard(name: 'Coach', firstMessage: 'Hello.');
      await library.addCharacter(card);
      await chat.setActiveCharacter(card);
      final original = chat.currentSessionId!;
      card.setBotCard(true, 'Give a short exercise.');
      await library.updateCharacter(card);
      await chat.startNewChat();
      expect(chat.messages.first.isBotProse, isTrue);
      await chat.loadSession(original);
      expect(chat.sessionGenSettings.soloBot, isNull);
      expect(chat.messages.first.isBotProse, isFalse);
    },
  );

  test(
    'OpenCode snapshot and live adoption retain Bot guidance and project policy',
    () async {
      final root = await Directory.systemTemp.createTemp('bot_coworker_');
      addTearDown(() => root.delete(recursive: true));
      final store = WaifuStore('${root.path}/store');
      final card = CharacterCard(
        name: 'Track Coach',
        scenario: 'README feedback.',
      )..setBotCard(true, 'Offer one small change at a time.');
      final folder = '${root.path}/project';
      final session = WaifuSession(
        folderRoot: folder,
        coworker: card,
        mode: WaifuMode.plan,
      );
      await store.saveLast(session);
      final restored = (await store.loadSession(folder))!;
      expect(restored.folderRoot, folder);
      expect(restored.mode, WaifuMode.plan);
      expect(restored.pathMode, WaifuPathMode.folderJail);
      final sameDate = DateTime(2026, 11, 20);
      expect(
        buildWaifuCardPersona(restored.coworker, now: sameDate),
        buildWaifuCardPersona(card, now: sameDate),
      );
      expect(
        buildWaifuPlanAgentPrompt(restored.coworker),
        contains('Scope: README feedback.'),
      );
      card.scenario = 'Guide a project outline.';
      expect(waifuAdoptCoworker(restored, card), isTrue);
      expect(
        buildWaifuOpenCodeAgentPrompt(restored.coworker),
        contains('Guide a project outline.'),
      );
    },
  );
}

Future<(ChatService, StorageService, CharacterRepository)>
openIsolatedChat() async {
  final root = Directory.systemTemp.createTempSync('bot_flows_');
  final originalPaths = PathProviderPlatform.instance;
  PathProviderPlatform.instance = SandboxPathProvider(root.path);
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'import_llmerta_porch_memories': false,
    'realism_default': false,
    'journal_enabled': false,
    'passage_of_time_default': false,
  });
  final db = AppDatabase.forTesting(sameIsolate: true);
  final storage = StorageService();
  await storage.initialized;
  final library = CharacterRepository(db, storage);
  final chat =
      ChatService(
          KoboldService(storage),
          UserPersonaService(db),
          storage,
          WorldRepository(storage, db),
        )
        ..setDatabase(db)
        ..setCharacterRepository(library);
  addTearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });
  return (chat, storage, library);
}
