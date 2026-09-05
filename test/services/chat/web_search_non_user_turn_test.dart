// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web search is an explicit direct-user-send capability. Group follow-ups,
// Scene Guests, and regenerate all reuse normal generation, but none may
// advertise web_search or reach HTTP.
//
// Guard proven red before passing: treating every GenerationMode.normal turn
// as eligible produced one extra tools round and one HTTP call in all three
// non-user path tests.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/services.dart';

class _RoutingLlm extends LLMService {
  final Set<int> lookupOnRounds = {};
  final List<GenerationParams> streams = [];
  int webSearchRounds = 0;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final tool in tools) (tool['function'] as Map?)?['name'] as String?,
    ];
    if (!names.contains(kWebSearchToolName)) return null;
    webSearchRounds++;
    if (!lookupOnRounds.contains(webSearchRounds)) {
      return const LlmToolResponse(calls: [], text: '');
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWebSearchToolName,
          arguments: {'query': 'non-user query $webSearchRounds'},
        ),
      ],
      text: '',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streams.add(params);
    yield 'Reply ${streams.length}.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'web-search-routing-test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_web_search_routing_')
              .path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _RoutingLlm llm;
  late int httpCalls;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _RoutingLlm();
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
    await storage.webSearchSettings.setSearchApiKey('routing-test-key');
    await storage.webSearchSettings.setWebSearchDefault(true);
    httpCalls = 0;
    chat.webSearchService.fetch = (uri, key) async {
      httpCalls++;
      return jsonEncode({
        'results': [
          {'title': 'Blocked', 'content': 'This request should not happen.'},
        ],
      });
    };
  });

  tearDown(() async {
    chat.dispose();
    storage.dispose();
    await db.close();
  });

  CharacterCard card(String name, String id) => CharacterCard(
    name: name,
    description: 'Exists only inside the web-search routing test.',
    firstMessage: '$name waits on the porch.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: false,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = id;

  test('group Next Character neither advertises nor reaches HTTP', () async {
    llm.lookupOnRounds.add(2);
    await db.insertGroup(
      GroupsCompanion.insert(id: 'web-search-group', name: 'Search Group'),
    );
    for (final (id, name) in [('member-a', 'Nia'), ('member-b', 'Rue')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'web-search-group',
          name: name,
          frontPorchExtensions: const Value(
            '{"realism_engine":{"realism_enabled":false}}',
          ),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'web-search-group', name: 'Search Group'),
      groupRepo: GroupChatRepository(storage, db),
    );

    await chat.sendMessage('Take a seat.');
    expect(chat.messages.last.sender, 'Nia');
    expect(
      llm.webSearchRounds,
      1,
      reason: 'the direct user send stays eligible',
    );
    expect(llm.streams.single.systemPrompt, contains(kWebSearchCharacterLine));

    await chat.triggerNextCharacter();

    expect(chat.messages.last.sender, 'Rue', reason: 'the follow-up path ran');
    expect(llm.webSearchRounds, 1);
    expect(httpCalls, 0);
    expect(
      llm.streams.last.systemPrompt,
      isNot(contains(kWebSearchCharacterLine)),
    );
  });

  test('Scene Guest generation neither advertises nor reaches HTTP', () async {
    llm.lookupOnRounds.add(1);
    await chat.setActiveCharacter(card('Host', 'routing-host'));

    await chat.generateGuestTurn(card('Guest', 'routing-guest'));

    expect(chat.messages.last.sender, 'Guest', reason: 'the guest path ran');
    expect(llm.webSearchRounds, 0);
    expect(httpCalls, 0);
    expect(
      llm.streams.single.systemPrompt,
      isNot(contains(kWebSearchCharacterLine)),
    );
  });

  test('Regenerate neither advertises nor reaches HTTP', () async {
    llm.lookupOnRounds.add(2);
    await chat.setActiveCharacter(card('Host', 'routing-regen'));
    await chat.sendMessage('Try a line.');
    expect(llm.webSearchRounds, 1);

    await chat.regenerateLastMessage();

    expect(
      chat.messages.last.swipes,
      hasLength(2),
      reason: 'the regen path ran',
    );
    expect(llm.webSearchRounds, 1);
    expect(httpCalls, 0);
    expect(
      llm.streams.last.systemPrompt,
      isNot(contains(kWebSearchCharacterLine)),
    );
  });

  test('only the direct send call site opens the search allow-list', () {
    final enabledAt = <String>[];
    final parts = Directory(
      'lib/services/chat',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));
    final enabled = RegExp(r'directUserSend:\s*true');
    for (final file in parts) {
      if (enabled.hasMatch(file.readAsStringSync())) enabledAt.add(file.path);
    }

    expect(enabledAt, ['lib/services/chat/chat_service_send.dart']);
  });
}
