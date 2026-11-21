// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/continue_glue.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/think_tags.dart';
import 'package:front_porch_ai/services/chat/doors/turn/scenario_prompt.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

import '../../../integration_test/support/e2e_sandbox.dart';
import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Scenario replaces the stock role and retains explicit prompt sources',
    () async {
      final (chat, storage, _) = await openIsolatedChat();
      final card = CharacterCard(name: 'Night Depot');
      final source = chat.promptAssembler.source;
      expect(
        storage.generationSettings.systemPrompt,
        GenerationSettings.defaultSystemPrompt,
      );
      expect(
        source.resolveOneToOneBase(card),
        GenerationSettings.defaultSystemPrompt,
      );
      expect(source.resolveOneToOneBase(card, scenario: true), isEmpty);

      await storage.generationSettings.setSystemPrompt('User voice.');
      expect(source.resolveOneToOneBase(card, scenario: true), 'User voice.');
      card.systemPrompt = 'Card voice.';
      expect(source.resolveOneToOneBase(card, scenario: true), 'Card voice.');
      chat.sessionGenSettings.systemPromptSource = 'user';
      expect(source.resolveOneToOneBase(card, scenario: true), 'User voice.');
    },
  );

  test(
    'Selecting a Scenario opening preserves prose through session reload',
    () async {
      final (chat, _, library) = await openIsolatedChat();
      final card = CharacterCard(
        name: 'Night Depot',
        firstMessage: 'The lights are on.',
        alternateGreetings: ['Keeper: “Last train.” *The bell rings.*'],
        frontPorchExtensions: FrontPorchExtensions(
          characterEmotion: 'warm',
          greetingSeeds: const [
            GreetingRealismSeed(characterEmotion: 'furious'),
          ],
        ),
      )..setScenarioCard(true, 'Ask where they want to go.');
      await library.addCharacter(card);
      await chat.setActiveCharacter(card);
      final original = chat.currentSessionId!;
      expect(chat.messages.first.isScenarioProse, isTrue);

      await chat.selectGreeting(1);
      expect(chat.messages.first.isScenarioProse, isTrue);
      expect(chat.characterEmotion, isNot('furious'));
      await chat.startNewChat();
      await chat.loadSession(original);
      final opening = chat.messages.first;
      expect(opening.isScenarioProse, isTrue);
      expect(chat.characterEmotion, isNot('furious'));
      expect(opening.displayText, card.alternateGreetings.single);
      expect(opening.toPromptHistoryLine(), startsWith('Narrator: Keeper:'));
    },
  );

  test(
    'Scenario voice excludes thinking split across sentences and chunks',
    () {
      final stream = ScenarioReplyStream(const []);
      final parts = [
        stream.speechText('Door opens. <th'),
        stream.speechText(
          'ink>First private sentence. Second private sentence. </THI',
        ),
        stream.speechText('NK> Keeper: “Go ahead.”'),
        stream.speechText(' <think>Unclosed.', done: true),
      ];
      expect(parts.join(), 'Door opens.  Keeper: “Go ahead.” ');
      expect(
        ScenarioReplyStream(const []).speechText('Look <', done: true),
        'Look <',
      );
    },
  );

  test('Scenario does not promote a thought-only reply to speech', () {
    const thinking = '<think>Consider whether to mention the lantern.</think>';
    expect(
      stripThinkTags(resolveMouthSpeech(thinking, retainThoughts: true)),
      isEmpty,
    );
    expect(
      resolveMouthSpeech(thinking),
      'Consider whether to mention the lantern.',
    );
  });

  test('Scenario sanitizer cannot turn tagged reasoning into prose', () {
    const rules = [
      OutputSanitizerRule(id: 0, find: '<think>', replace: ''),
      OutputSanitizerRule(id: 1, find: '</think>', replace: ''),
      OutputSanitizerRule(id: 2, find: 'lantern', replace: 'lamp'),
    ];
    const thought = '<think>Decide whether to mention the lantern.</think>';
    const moreThought = '<think>Consider where the clock is.</think>';
    expect(sanitizeScenarioReply(thought, rules), thought);
    final mixed = sanitizeScenarioReply(
      '$thought$moreThought The lantern glows.',
      rules,
    );
    expect(mixed, contains(thought));
    expect(mixed, contains(moreThought));
    expect(stripThinkTags(mixed), 'The lamp glows.');
  });

  test('Scenario Continue strips mixed-case thoughts before prose rules', () {
    const rules = [
      OutputSanitizerRule(id: 0, find: '<think>', replace: ''),
      OutputSanitizerRule(id: 1, find: '</think>', replace: ''),
      OutputSanitizerRule(id: 2, find: 'lantern', replace: 'lamp'),
    ];
    const prefix = 'The player waits.';
    const next =
        '<THINK>Consider whether the player has a key.</Think> The lantern glows.';
    final visible = scenarioContinuationProse(next);
    expect(visible, 'The lantern glows.');
    expect(
      glueContinueText(prefix, sanitizeScenarioReply(visible, rules)),
      'The player waits. The lamp glows.',
    );
    expect(scenarioContinuationProse('Visible. <THINK>Unclosed.'), 'Visible.');
  });

  test('Card keeps full rules while the session keeps a bounded snapshot', () {
    final rule = '🧭' * 2000 + 'Ask one question.';
    final card = CharacterCard(name: 'Night Depot')
      ..setScenarioCard(true, rule);
    expect(card.facilitationRules, rule);
    expect(ScenarioCardSnapshot.fromCard(card)!.rules, '🧭' * 2000);
  });

  test('Old Scenario rules survive a saved card edit and a new chat', () async {
    final (chat, _, library) = await openIsolatedChat();
    const firstRules = 'Offer the west platform.';
    const nextRules = 'Offer the east platform.';
    final card = CharacterCard(
      name: 'Night Depot',
      firstMessage: 'The lights are on.',
    )..setScenarioCard(true, firstRules);
    await library.addCharacter(card);
    await chat.setActiveCharacter(card);
    final original = chat.currentSessionId!;
    expect(chat.sessionGenSettings.soloScenario?.rules, firstRules);

    card.setScenarioCard(true, nextRules);
    await library.updateCharacter(card);
    await chat.startNewChat();
    expect(chat.currentSessionId, isNot(original));
    expect(chat.sessionGenSettings.soloScenario?.rules, nextRules);
    await chat.loadSession(original);
    expect(chat.sessionGenSettings.soloScenario?.rules, firstRules);
    expect(chat.messages.first.isScenarioProse, isTrue);
  });
}

Future<(ChatService, StorageService, CharacterRepository)>
openIsolatedChat() async {
  final root = Directory.systemTemp.createTempSync('scenario_polish_');
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
