// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Continue = regen for speaker identity (full-codebase audit P0):
//   * Scene Guest Continue must pass guestSpeaker so the host-ban cannot
//     sit on a guest suffix.
//   * Group Continue uses the id-first resolver and refuses to guess
//     when two members share a name.
//
// Proven red: restore firstWhere-by-name in _generateResponse and the
// group Continue prompt test picks the first Alex; delete the
// `_sceneGuestForMessage` infer and the source pin fails.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_contid_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  final List<String> systems = [];
  final List<String> prompts = [];
  String reply = '*They keep talking.*';
  int pocketsPrompts = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      systems.add(params.systemPrompt!);
    }
    prompts.add(params.prompt);
    if (params.prompt.contains('You are keeping track of what')) {
      pocketsPrompts++;
      yield '{"inventory_ops": []}';
      return;
    }
    if (params.systemPrompt != null) {
      yield reply;
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> drainUntil(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'group Continue uses the stamped id when two members share a name',
    () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-alex', name: 'Two Alexes'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-north',
          groupId: 'grp-alex',
          name: 'Alex',
          personality: const Value('Alex from the NORTH porch, maple syrup.'),
          systemPrompt: const Value('You are Alex from the NORTH porch.'),
          avatarFilename: const Value('Alex_north.png'),
          frontPorchExtensions: Value(
            jsonEncode({
              'realism_engine': {'inventory': <String, dynamic>{}},
            }),
          ),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-south',
          groupId: 'grp-alex',
          name: 'Alex',
          personality: const Value('Alex from the SOUTH dock, salt air.'),
          systemPrompt: const Value('You are Alex from the SOUTH dock.'),
          avatarFilename: const Value('Alex_south.png'),
          frontPorchExtensions: Value(
            jsonEncode({
              'realism_engine': {'inventory': <String, dynamic>{}},
            }),
          ),
        ),
      );
      await chat.setActiveGroup(
        GroupChat(id: 'grp-alex', name: 'Two Alexes'),
        groupRepo: GroupChatRepository(storage, db),
      );

      final south = chat.groupCharacters.firstWhere(
        (c) => c.personality.contains('SOUTH'),
      );
      chat.setNextCharacter(south);

      llm.reply = '*South Alex leans on the rail.*';
      await chat.sendMessage('Say something, South.');
      await drainUntil(
        () =>
            chat.messages.any((m) => !m.isUser && m.sender != 'System') &&
            !chat.isGenerating &&
            !chat.isSettlingTurn,
      );

      llm.systems.clear();
      llm.reply = ' The tide is loud tonight.';
      await chat.continueGeneration();
      await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

      expect(
        llm.systems,
        isNotEmpty,
        reason: 'Continue must fire a generation',
      );
      final joined = llm.systems.join('\n');
      // Group prompts list every member's persona. The YOU ARE line is
      // who Continue picked. first-match-by-name would have said NORTH.
      expect(
        joined,
        contains('You are Alex from the SOUTH dock.'),
        reason: 'Continue must keep speaking as the stamped South Alex',
      );
      expect(
        joined,
        isNot(contains('You are Alex from the NORTH porch.')),
        reason: 'first-match-by-name would have loaded the first Alex',
      );
    },
  );

  test(
    'Scene Guest Continue uses the guest-turn note, not the host-ban',
    () async {
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-host',
          name: 'Mara',
          imagePath: const Value('/tmp/Mara_host.png'),
          firstMessage: const Value('The porch light hums.'),
        ),
      );
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'guest-riley',
          name: 'Riley',
          imagePath: const Value('/tmp/Riley_guest.png'),
          firstMessage: const Value('Riley waves from the steps.'),
        ),
      );
      final host = CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        imagePath: '/tmp/Mara_host.png',
        frontPorchExtensions: FrontPorchExtensions(
          inventory: {
            'carrying': ['car keys'],
          },
        ),
      )..dbId = 'char-host';
      await chat.setActiveCharacter(host);

      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-guest-cont-id',
          characterId: const Value('char-host'),
          groupRealismState: const Value('{"sceneGuests":["guest-riley"]}'),
        ),
      );
      for (final (i, seed) in const [
        ('Mara', false, 'Mara_host'),
        ('You', true, null),
        ('Riley', false, 'Riley_guest'),
      ].indexed) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'gcont-$i',
            sessionId: 'sess-guest-cont-id',
            position: i,
            sender: seed.$1,
            isUser: seed.$2,
            characterId: Value(seed.$3),
            swipes: const Value('["*The porch light hums while they talk.*"]'),
          ),
        );
      }
      await chat.loadSession('sess-guest-cont-id');
      for (var i = 0; i < 200 && chat.sceneGuestCards.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        chat.sceneGuestCards.map((c) => c.name),
        contains('Riley'),
        reason: 'the guest must be present so Continue can speak as them',
      );

      llm.systems.clear();
      llm.prompts.clear();
      llm.pocketsPrompts = 0;
      llm.reply = ' Riley keeps going.';
      await chat.continueGeneration();
      await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

      final blob = [...llm.systems, ...llm.prompts].join('\n');
      expect(
        blob,
        contains('SCENE GUEST TURN'),
        reason: 'Continue of a guest bubble must switch identity like regen',
      );
      expect(
        blob,
        isNot(contains('Stay entirely as Mara')),
        reason: 'the host-ban must not sit on a guest suffix',
      );
      expect(
        llm.pocketsPrompts,
        0,
        reason: 'present-guest Continue must not score the host kit',
      );
    },
  );
}
