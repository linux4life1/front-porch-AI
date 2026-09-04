// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Dynamic Responses are autonomous: an idle timer may write another
// character turn, but it must never advertise web_search or reach HTTP
// without a user-initiated send.
//
// Proven red: before the autonomous-turn gate, the idle tools count and
// HTTP count were both 1.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../golden/support/fakes.dart';

class _IdleSearchLlm extends LLMService {
  final List<String> webSearchPrompts = [];
  int streamCalls = 0;
  int idleStreamCalls = 0;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final tool in tools) (tool['function'] as Map?)?['name'] as String?,
    ];
    if (names.contains('report_ping')) {
      return const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
        ],
        text: '',
      );
    }
    if (!names.contains(kWebSearchToolName)) return null;
    webSearchPrompts.add(params.prompt);
    if (webSearchPrompts.length == 1) {
      return const LlmToolResponse(calls: [], text: '');
    }
    return const LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWebSearchToolName,
          arguments: {'query': 'idle weather'},
        ),
      ],
      text: '',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamCalls++;
    if (streamCalls > 1) {
      idleStreamCalls++;
      yield '*The quiet idle snapshot continues.*';
      return;
    }
    yield 'The user-initiated reply.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'idle-search-test';
}

class _IdleLlmProvider extends FakeLLMProvider {
  _IdleLlmProvider(this._service)
    : super(activeBackend: BackendType.openRouter);

  final LLMService _service;
  final OpenRouterService _remote = OpenRouterService();

  @override
  LLMService get activeService => _service;

  @override
  OpenRouterService get openRouterService => _remote;

  @override
  void dispose() {
    _remote.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_idle_search_').path;
        }
        return null;
      });

  test('Dynamic Responses neither advertise web search nor call HTTP', () async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    final llm = _IdleSearchLlm();
    final provider = _IdleLlmProvider(llm);
    final chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..setLLMProvider(provider);
    addTearDown(() async {
      chat.dispose();
      provider.dispose();
      await db.close();
    });

    await storage.initialized;
    await storage.setAutostartOnChatOpen(false);
    await storage.webSearchSettings.setSearchApiKey('test-key');
    await storage.webSearchSettings.setWebSearchDefault(true);
    await storage.generationSettings.setDynamicResponses(true);
    await storage.generationSettings.setDynamicResponseInterval(3600);
    await storage.generationSettings.setDynamicResponseMaxMessages(1);
    var httpCalls = 0;
    chat.webSearchService.fetch = (uri, key) async {
      httpCalls++;
      return jsonEncode({
        'results': [
          {'title': 'Idle weather', 'content': 'This must never be fetched.'},
        ],
      });
    };

    final card = CharacterCard(
      name: 'Idle Character',
      description: 'Exists only inside the idle web-search test.',
      firstMessage: 'The porch is quiet.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'idle-search-character';
    await chat.setActiveCharacter(card);
    await chat.sendMessage('Hello');
    chat.debugFireIdleTimerForTest();

    for (
      var i = 0;
      i < 2500 &&
          (llm.idleStreamCalls == 0 ||
              chat.isGenerating ||
              chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(
      llm.idleStreamCalls,
      1,
      reason:
          'the test must exercise the real idle generation path; '
          'streams=${llm.streamCalls}, searches=${llm.webSearchPrompts.length}, '
          'messages=${chat.messages.map((m) => m.text).toList()}',
    );
    expect(
      llm.webSearchPrompts,
      hasLength(1),
      reason: 'an autonomous turn must not receive the web_search tool',
    );
    expect(
      httpCalls,
      0,
      reason: 'an idle tick must never reach Tavily or Wikipedia',
    );
    expect(
      chat.webSearchService.httpCalls,
      0,
      reason:
          'the service-wide counter covers both keyed Tavily and keyless '
          'Wikipedia requests',
    );
  });
}
