// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Model-initiated web_search: the tools payload includes web_search, a
// web_search call runs the HTTP client, empty results inject the
// empty-result fragment, Continue does not call search, regen hits cache.
//
// Guards proven to fail before passing:
//   * omit web_search from the tools list → payload assertion goes red
//   * skip HTTP on a cache miss → httpCalls stays 0
//   * Continue still advertising tools → continueToolsCalls > 0
//   * regen skipping the cache → httpCalls increments

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/search_injection.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_websearch_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String replyText = '*those robes.. you\'re a Quincy?!*';
  String? searchQuery = 'Wandenreich Bleach';
  final List<List<Map<String, dynamic>>> toolsPayloads = [];
  final List<GenerationParams> toolsParams = [];
  final List<String> streamPrompts = [];
  int generateWithToolsCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamPrompts.add(params.prompt);
    if (params.systemPrompt != null) {
      yield replyText;
      return;
    }
    yield '';
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    generateWithToolsCalls++;
    toolsPayloads.add(tools);
    toolsParams.add(params);
    final names = [
      for (final t in tools) (t['function'] as Map?)?['name'] as String?,
    ];
    if (!names.contains(kWebSearchToolName)) return null;
    final q = searchQuery;
    if (q == null) {
      return LlmToolResponse(calls: const [], text: replyText);
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(name: kWebSearchToolName, arguments: {'query': q}),
      ],
      text: '',
    );
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
  late int httpCalls;
  late List<String> fetchedQueries;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    httpCalls = 0;
    fetchedQueries = [];
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
    await storage.webSearchSettings.setSearchApiKey('bs-test');
    await storage.webSearchSettings.setWebSearchDefault(true);
    chat.webSearchService.fetch = (uri, key) async {
      httpCalls++;
      fetchedQueries.add(uri.queryParameters['q'] ?? '');
      return jsonEncode({
        'results': [
          {
            'title': 'Wandenreich',
            'content': 'The Wandenreich is the Quincy empire from Bleach.',
          },
        ],
      });
    };
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  CharacterCard card() => CharacterCard(
    name: 'Mara',
    description: 'Exists only inside the web-search turn test.',
    firstMessage: 'The porch light hums.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: false,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = 'char-search-1';

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test(
    'a user line with an unknown term advertises web_search and HTTPs',
    () async {
      // Reproduce the live-OR bug: chat opens with the global OFF, then
      // Porch Life is flipped ON without reopening. Seed-time alone
      // would leave the tool dark; check-time OR must pick it up.
      await storage.webSearchSettings.setWebSearchDefault(false);
      await chat.setActiveCharacter(card());
      expect(chat.webSearchEnabled, isFalse);
      await storage.webSearchSettings.setWebSearchDefault(true);
      expect(
        chat.webSearchEnabled,
        isTrue,
        reason: 'Porch Life global alone must activate an already-open chat',
      );

      await chat.sendMessage('I put on my starched white wandenreich robes');
      await drainTurn();

      expect(
        llm.toolsPayloads,
        isNotEmpty,
        reason: 'feature on + key + tools-capable → generateWithTools',
      );
      final names = [
        for (final payload in llm.toolsPayloads)
          for (final t in payload) (t['function'] as Map?)?['name'] as String?,
      ];
      expect(names, contains(kWebSearchToolName));
      expect(httpCalls, 1);

      final reply = chat.messages.last;
      expect(reply.isUser, isFalse);
      expect(reply.text, contains('Quincy'));
      final receipt = reply.activeMetadata?['search_receipt'];
      expect(receipt, isNotNull, reason: 'receipt chip rides the reply');
      expect((receipt as Map)['query'], contains('Wandenreich'));
    },
  );

  test(
    'empty search results inject the empty-result fragment, not a fake wiki',
    () async {
      llm.searchQuery = 'zxqwt';
      chat.webSearchService.fetch = (uri, key) async {
        httpCalls++;
        return jsonEncode({'results': []});
      };
      await chat.setActiveCharacter(card());
      await chat.sendMessage('what is zxqwt');
      await drainTurn();

      expect(
        llm.streamPrompts.any(
          (p) => p.contains(webSearchEmptyResultFragment('zxqwt')),
        ),
        isTrue,
        reason: 'the model must be told it does not know — not handed a wiki',
      );
    },
  );

  test('Continue does not call search', () async {
    await chat.setActiveCharacter(card());
    llm.searchQuery = null;
    await chat.sendMessage('hello there');
    await drainTurn();
    final toolsBefore = llm.generateWithToolsCalls;

    llm.replyText = ' She tugs the sleeve straight.';
    await chat.continueGeneration();
    await drainTurn();

    expect(
      llm.generateWithToolsCalls,
      toolsBefore,
      reason: 'Continue extends the reply; it must not re-open tools',
    );
  });

  test(
    'tools round is told to search unknown facts; the stream is not',
    () async {
      await chat.setActiveCharacter(card());
      await chat.sendMessage('what is the weather in Spokane');
      await drainTurn();

      expect(llm.toolsParams, isNotEmpty, reason: 'tools round-trip must fire');
      GenerationParams? searchParams;
      for (var i = 0; i < llm.toolsPayloads.length; i++) {
        final names = [
          for (final t in llm.toolsPayloads[i])
            (t['function'] as Map?)?['name'] as String?,
        ];
        if (names.contains(kWebSearchToolName)) {
          searchParams = llm.toolsParams[i];
          break;
        }
      }
      expect(
        searchParams,
        isNotNull,
        reason: 'web_search must be on a tools payload, not only report_ping',
      );
      expect(
        searchParams!.prompt,
        contains(kWebSearchDecisionCue),
        reason:
            'without a last-token cue the RP suffix wins and they only '
            'search when the user OOC-forces it',
      );
      expect(searchParams.systemPrompt, contains(kWebSearchDecisionCue));
      expect(
        searchParams.reasoningEnabled,
        isTrue,
        reason:
            'the lookup check is a think phase so the model can notice '
            'what it does not know; the in-character stream keeps the '
            'user\'s reasoning setting',
      );
      expect(
        llm.streamPrompts.any((p) => p.contains(kWebSearchDecisionCue)),
        isFalse,
        reason:
            'the decision cue is a tools-round stage direction; the '
            'in-character stream must not see it',
      );
    },
  );

  test('no tool call still streams the in-character reply', () async {
    llm.searchQuery = null;
    llm.replyText = 'Hey there.';
    await chat.setActiveCharacter(card());
    await chat.sendMessage('hello');
    await drainTurn();

    expect(
      llm.streamPrompts,
      isNotEmpty,
      reason:
          'the think-to-search round is not the bubble — even a no-lookup '
          'turn must stream the in-character reply',
    );
    expect(chat.messages.last.isUser, isFalse);
    expect(chat.messages.last.text, contains('Hey there'));
  });

  test('regen of a searched turn does not HTTP', () async {
    await chat.setActiveCharacter(card());
    await chat.sendMessage('I put on my starched white wandenreich robes');
    await drainTurn();
    expect(httpCalls, 1);

    llm.replyText = '*those robes.. a Quincy, then.*';
    await chat.regenerateLastMessage();
    await drainTurn();
    expect(
      httpCalls,
      1,
      reason:
          'session cache must serve the same query on regen; '
          'fetched $fetchedQueries',
    );
  });
}
