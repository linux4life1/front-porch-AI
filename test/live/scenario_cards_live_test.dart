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
    'Scenario carries its facilitator role through send, Continue and regen',
    () async {
      HttpOverrides.global = null;
      final root = await Directory.systemTemp.createTemp('fpai_live_scenario_');
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
              modelName: 'qwen-local-scenario-test',
            );
      addTearDown(() => disposeChatThenCloseDb(chat, db));

      final observatory =
          CharacterCard(
            name: 'Flooded Observatory',
            scenario: 'A flooded observatory has a radio on its landing.',
            firstMessage:
                'Water reaches the first stair. You see the radio and a ladder.',
          )..setScenarioCard(
            true,
            'Describe consequences, then let the player choose.',
          );
      expect(
        await persistCharacterCard(library, storage, observatory),
        isNotNull,
      );
      await chat.setActiveCharacter(observatory);
      chat.sessionGenSettings = ChatGenerationSettings(
        maxLength: 110,
        temperature: 0.2,
      );
      expect(chat.messages.last.isScenarioProse, isTrue);

      await chat.sendMessage(
        'I call up the stairs to see if anyone can hear me.',
      );
      final first = chat.messages.last;
      final firstBody = first.displayText.trim();
      expect(firstBody, isNotEmpty);
      expect(first.isScenarioProse, isTrue);
      expect(first.sender, observatory.name);
      expect(
        chat.lastPromptSections.values.join('\n'),
        contains('Facilitate the scenario'),
      );
      expect(
        chat.lastPromptSections.values.join('\n'),
        contains(observatory.scenario),
      );
      print('Synthetic observatory reply: $firstBody');

      await chat.continueGeneration();
      expect(chat.messages.last.isScenarioProse, isTrue);
      expect(chat.messages.last.displayText.trim(), startsWith(firstBody));

      await chat.regenerateLastMessage();
      final regenerated = chat.messages.last;
      expect(regenerated.isScenarioProse, isTrue);
      expect(regenerated.swipes.length, greaterThan(1));
      expect(
        chat.lastPromptSections.values.join('\n'),
        contains('Facilitate the scenario'),
      );
      await chat.swipeMessage(chat.messages.length - 1, -1);
      expect(chat.messages.last.isScenarioProse, isTrue);

      final countBeforeDraft = chat.messages.length;
      String userDraft = '';
      await chat.impersonateUser(onToken: (text) => userDraft = text);
      expect(userDraft.trim(), isNotEmpty);
      expect(chat.messages.length, countBeforeDraft);
      chat.editMessage(
        chat.messages.length - 1,
        'A count of three taps echoes from above.',
      );
      expect(chat.messages.last.isScenarioProse, isTrue);
      await chat.deleteMessage(chat.messages.length - 1);
      expect(chat.messages.last.isUser, isTrue);

      final blankSetting =
          CharacterCard(
            name: 'Crossroads Dispatch',
            firstMessage:
                'What terrain would you like this journey to take place in?',
          )..setScenarioCard(
            true,
            'Find out the setting before introducing the scene.',
          );
      expect(
        await persistCharacterCard(library, storage, blankSetting),
        isNotNull,
      );
      await chat.setActiveCharacter(blankSetting);
      chat.sessionGenSettings = ChatGenerationSettings(
        maxLength: 110,
        temperature: 0.2,
      );
      await chat.sendMessage('Start at a snowy mountain station, after dark.');
      final answer = chat.messages.last;
      expect(answer.isScenarioProse, isTrue);
      expect(answer.displayText.trim(), isNotEmpty);
      expect(
        chat.lastPromptSections.values.join('\n'),
        contains('snowy mountain station'),
      );
      print('Synthetic choose-a-setting reply: ${answer.displayText.trim()}');

      final lookout = CharacterCard(
        name: 'Lookout',
        description: 'A station attendant waiting for the last train.',
      );
      expect(await persistCharacterCard(library, storage, lookout), isNotNull);
      final group = await chat.forkToGroupChat(
        [lookout],
        groups,
        groupName: 'Last Train',
        scenario: 'A snowy mountain station, after dark.',
      );
      expect(group, isNotNull);
      final host = chat.groupCharacters.firstWhere(
        (member) => member.name == blankSetting.name,
      );
      final ordinary = chat.groupCharacters.firstWhere(
        (member) => member.name == lookout.name,
      );
      chat.sessionGenSettings = ChatGenerationSettings(
        maxLength: 80,
        temperature: 0.2,
      );
      chat.queueSpeaker(host);
      await chat.sendMessage('I wait next to the ticket booth and listen.');
      expect(chat.messages.last.sender, host.name);
      expect(chat.messages.last.isScenarioProse, isTrue);
      expect(
        chat.lastPromptSections.values.join(' '),
        contains('Other named chat participants'),
      );
      chat.queueSpeaker(ordinary);
      await chat.sendMessage('Is this where I catch the last train?');
      expect(chat.messages.last.sender, ordinary.name);
      expect(chat.messages.last.isScenarioProse, isFalse);
      expect(
        chat.lastPromptSections.values.join(' '),
        isNot(contains('Facilitate the scenario')),
      );
      expect(await chat.removeCharacterFromGroup(ordinary, groups), isTrue);
      expect(chat.activeCharacter?.dbId, blankSetting.dbId);
      expect(
        chat.sessionGenSettings.soloScenario?.rules,
        blankSetting.facilitationRules,
      );
    },
    skip: liveEngineSkip,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
