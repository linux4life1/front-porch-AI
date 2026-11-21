// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

@Tags(['kobold_live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character/character_card_edits.dart';

import '../../integration_test/support/e2e_sandbox.dart';
import '../helpers/chat_db_teardown.dart';
import 'live_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Bot responds to the user’s setting and keeps its voice through reply paths',
    () async {
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp('fpai_live_bot_');
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = SandboxPathProvider(root.path);
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'import_llmerta_porch_memories': false,
        'realism_default': false,
        'passage_of_time_default': false,
        'pockets_enabled': false,
        'journal_enabled': false,
      });
      addTearDown(() async {
        PathProviderPlatform.instance = originalPaths;
        await root.delete(recursive: true);
      });

      final port = await freePort();
      final engine = await LiveEngine.start(
        await copyEngineInto(Directory('${root.path}/engine')),
        [
          '--model',
          liveEngineModel,
          '--port',
          '$port',
          '--host',
          '127.0.0.1',
          '--usecpu',
          '--threads',
          '4',
          '--contextsize',
          '4096',
          '--quiet',
        ],
      );
      addTearDown(() async {
        engine.process.kill();
        await engine.process.exitCode;
      });
      await waitForLiveModel(port);
      final storage = StorageService();
      await storage.initialized;
      final db = AppDatabase.forTesting();
      final receiver = 'http://127.0.0.1:$port';
      final library = CharacterRepository(db, storage);
      final groups = GroupChatRepository(storage, db);
      final chat =
          ChatService(
              KoboldService(storage)..setBaseUrl(receiver),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(library)
            ..setGroupChatRepository(groups)
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '$receiver/v1',
              modelName: 'qwen-local-bot-test',
            );
      addTearDown(() => disposeChatThenCloseDb(chat, db));

      CharacterCard coach({required bool bot}) {
        final card = CharacterCard(
          name: bot ? 'Juniper' : 'Juniper Control',
          description:
              'A patient coach who helps the user rehearse a short introduction.',
          scenario: 'Public-speaking practice for an interview introduction.',
          firstMessage:
              'Read your introduction aloud once, then tell me what felt awkward.',
        );
        if (bot) {
          card.setBotCard(
            true,
            'Offer one introduction exercise at a time. '
            'If speaking is impractical, give the user one sentence to write silently.',
          );
        }
        return card;
      }

      const train =
          'I am on a quiet train and cannot speak. Help me silently rehearse '
          'the first sentence of my interview introduction by typing it on my phone.';
      final ordinaryCard = coach(bot: false);
      expect(
        await persistCharacterCard(library, storage, ordinaryCard),
        isNotNull,
      );
      await chat.setActiveCharacter(ordinaryCard);
      chat.sessionGenSettings = ChatGenerationSettings(
        maxLength: 110,
        temperature: 0.2,
      );
      await chat.sendMessage(train);
      expect(chat.messages.last.isBotProse, isFalse);
      print('Character control: ${chat.messages.last.displayText.trim()}');

      final bot = coach(bot: true);
      expect(await persistCharacterCard(library, storage, bot), isNotNull);
      await chat.setActiveCharacter(bot);
      chat.sessionGenSettings = ChatGenerationSettings(
        maxLength: 110,
        temperature: 0.2,
      );
      expect(chat.messages.last.isBotProse, isTrue);
      await chat.sendMessage(train);
      final first = chat.messages.last;
      final firstBody = first.displayText.trim();
      expect(firstBody, isNotEmpty);
      expect(first.isBotProse, isTrue, reason: firstBody);
      expect(first.sender, bot.name);
      expect(firstBody, isNot(startsWith('${bot.name}:')));
      final fullPrompt = chat.lastPromptSections.values.join('\n');
      expect(fullPrompt, contains('you are the Bot on the speaker card'));
      expect(bot.scenario.allMatches(fullPrompt), hasLength(1));
      expect(
        firstBody,
        matches(
          RegExp(
            r'silent|mentally|in your head|writ|typ',
            caseSensitive: false,
          ),
        ),
      );
      print('Bot reply: $firstBody');

      await chat.continueGeneration();
      expect(chat.messages.last.isBotProse, isTrue);
      expect(chat.messages.last.displayText.trim(), startsWith(firstBody));

      await chat.regenerateLastMessage();
      expect(chat.messages.last.isBotProse, isTrue);
      expect(chat.messages.last.swipes.length, greaterThan(1));
      await chat.swipeMessage(chat.messages.length - 1, -1);
      expect(chat.messages.last.isBotProse, isTrue);

      final countBeforeDraft = chat.messages.length;
      String userDraft = '';
      await chat.impersonateUser(onToken: (text) => userDraft = text);
      expect(userDraft.trim(), isNotEmpty);
      expect(chat.messages.length, countBeforeDraft);
      chat.editMessage(
        chat.messages.length - 1,
        'Try one sentence silently first.',
      );
      expect(chat.messages.last.isBotProse, isTrue);
      await chat.deleteMessage(chat.messages.length - 1);
      expect(chat.messages.last.isUser, isTrue);

      final ordinary = CharacterCard(
        name: 'Lookout',
        description: 'A train attendant.',
      );
      expect(await persistCharacterCard(library, storage, ordinary), isNotNull);
      final group = await chat.forkToGroupChat(
        [ordinary],
        groups,
        groupName: 'Commuters',
      );
      expect(group, isNotNull);
      final host = chat.groupCharacters.firstWhere(
        (member) => member.name == bot.name,
      );
      final attendant = chat.groupCharacters.firstWhere(
        (member) => member.name == ordinary.name,
      );
      chat.sessionGenSettings = ChatGenerationSettings(
        maxLength: 75,
        temperature: 0.2,
      );
      chat.queueSpeaker(host);
      await chat.sendMessage('What could I type to practice my introduction?');
      expect(chat.messages.last.sender, host.name);
      expect(chat.messages.last.isBotProse, isTrue);
      expect(
        bot.scenario.allMatches(chat.lastPromptSections.values.join(' ')),
        hasLength(1),
      );
      final partial = chat.messages.last.displayText.trim();
      chat.queueSpeaker(attendant);
      await chat.continueGeneration();
      expect(chat.messages.last.sender, host.name);
      expect(chat.messages.last.isBotProse, isTrue);
      expect(chat.messages.last.displayText.trim(), startsWith(partial));
      chat.queueSpeaker(attendant);
      await chat.sendMessage('Are we almost at the next stop?');
      expect(chat.messages.last.sender, attendant.name);
      expect(chat.messages.last.isBotProse, isFalse);
      expect(
        chat.lastPromptSections.values.join(' '),
        isNot(contains('Scope: ${bot.scenario}')),
      );
      expect(await chat.removeCharacterFromGroup(attendant, groups), isTrue);
      expect(chat.activeCharacter?.dbId, bot.dbId);
      expect(
        chat.sessionGenSettings.soloBot?.instructions,
        bot.behaviorInstructions,
      );
    },
    skip: liveEngineSkip,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
