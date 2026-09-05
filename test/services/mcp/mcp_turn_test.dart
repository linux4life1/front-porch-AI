// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Production-path MCP round-trip: catalog advertise, inject, receipt,
// Continue skip, disabled no-op, disconnect → empty-result fragment.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_mcp_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String replyText = 'The container is healthy.';
  String? toolName = 'list_containers';
  final List<List<Map<String, dynamic>>> toolsPayloads = [];
  final List<String> streamPrompts = [];
  int generateWithToolsCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streamPrompts.add(params.prompt);
    yield replyText;
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    generateWithToolsCalls++;
    toolsPayloads.add(tools);
    final names = [
      for (final t in tools) (t['function'] as Map?)?['name'] as String?,
    ];
    final wanted = toolName;
    if (wanted == null || !names.contains(wanted)) {
      return null;
    }
    return LlmToolResponse(
      calls: [LlmToolCall(name: wanted, arguments: const {})],
      text: '',
    );
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

http.Response _rpcOk(http.BaseRequest request, Map<String, dynamic> result) {
  final body = request is http.Request ? request.body : '';
  int? id;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) id = decoded['id'] as int?;
  } catch (_) {}
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;
  late int mcpCalls;

  setUp(() async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    mcpCalls = 0;
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
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  CharacterCard card() => CharacterCard(
    name: 'Mara',
    description: 'Exists only inside the MCP turn test.',
    firstMessage: 'The porch light hums.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: false,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = 'char-mcp-1';

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

  Future<McpServerConfig> _connectDocker({bool listOk = true}) async {
    final server = await storage.mcpSettings.addServer(
      displayName: 'Docker',
      url: 'http://127.0.0.1:9/mcp',
    );
    chat.mcpHub.sendRequest = (request) async {
      final body = request is http.Request ? request.body : '';
      if (body.contains('"initialize"')) {
        return _rpcOk(request, {'protocolVersion': '2025-03-26'});
      }
      if (body.contains('notifications/initialized')) {
        return http.Response('', 202);
      }
      if (body.contains('tools/list')) {
        if (!listOk) return http.Response('fail', 500);
        return _rpcOk(request, {
          'tools': [
            {
              'name': 'list_containers',
              'description': 'List containers',
              'inputSchema': {'type': 'object', 'properties': {}},
            },
          ],
        });
      }
      if (body.contains('tools/call')) {
        mcpCalls++;
        return _rpcOk(request, {
          'content': [
            {'type': 'text', 'text': 'web is healthy'},
          ],
        });
      }
      return http.Response('no', 404);
    };
    await chat.mcpHub.connect(server.id);
    return server;
  }

  test('enabled server tools are advertised and tools/call runs', () async {
    final server = await _connectDocker();
    await chat.setActiveCharacter(card());
    await chat.setMcpServerEnabledForChat(server.id, true);

    await chat.sendMessage('are the containers up?');
    await drainTurn();

    expect(llm.toolsPayloads, isNotEmpty);
    final names = [
      for (final payload in llm.toolsPayloads)
        for (final t in payload) (t['function'] as Map?)?['name'] as String?,
    ];
    expect(names, contains('list_containers'));
    expect(names, isNot(contains('docker__list_containers')));
    expect(mcpCalls, 1);

    final reply = chat.messages.last;
    expect(reply.activeMetadata?['mcp_receipt'], isNotNull);
    expect(
      (reply.activeMetadata!['mcp_receipt'] as Map)['tool'],
      'list_containers',
    );
    expect(
      llm.streamPrompts.any((p) => p.contains('UNTRUSTED EXTERNAL TOOL DATA')),
      isTrue,
    );
    expect(reply.text, isNot(contains('"content"')));
  });

  test('disabled server: catalog omits tools; a call is a no-op', () async {
    await _connectDocker();
    await chat.setActiveCharacter(card());
    // Seed default is off — do not enable.
    expect(chat.mcpEnabledServerIds, isEmpty);

    await chat.sendMessage('are the containers up?');
    await drainTurn();

    expect(mcpCalls, 0);
    final names = [
      for (final payload in llm.toolsPayloads)
        for (final t in payload) (t['function'] as Map?)?['name'] as String?,
    ];
    expect(names, isNot(contains('list_containers')));
  });

  test('Continue does not call MCP', () async {
    final server = await _connectDocker();
    await chat.setActiveCharacter(card());
    await chat.setMcpServerEnabledForChat(server.id, true);
    llm.toolName = null;
    await chat.sendMessage('hello there');
    await drainTurn();
    final toolsBefore = llm.generateWithToolsCalls;
    final callsBefore = mcpCalls;

    llm.replyText = ' She tugs the sleeve straight.';
    await chat.continueGeneration();
    await drainTurn();

    expect(llm.generateWithToolsCalls, toolsBefore);
    expect(mcpCalls, callsBefore);
  });

  test('disconnect mid-turn injects the empty-result fragment', () async {
    final server = await _connectDocker();
    await chat.setActiveCharacter(card());
    await chat.setMcpServerEnabledForChat(server.id, true);
    await chat.mcpHub.disconnect(server.id);

    await chat.sendMessage('are the containers up?');
    await drainTurn();

    expect(
      mcpCalls,
      0,
      reason: 'disconnected server is absent from the catalog',
    );
    chat.mcpHub.sendRequest = (request) async {
      final body = request is http.Request ? request.body : '';
      if (body.contains('tools/call')) {
        mcpCalls++;
        return http.Response('timeout', 504);
      }
      if (body.contains('"initialize"') || body.contains('tools/list')) {
        return _rpcOk(request, {
          if (body.contains('tools/list'))
            'tools': [
              {
                'name': 'list_containers',
                'description': 'List',
                'inputSchema': {'type': 'object'},
              },
            ]
          else
            'protocolVersion': '2025-03-26',
        });
      }
      return http.Response('', 202);
    };
    await chat.mcpHub.connect(server.id);
    llm.generateWithToolsCalls = 0;
    await chat.sendMessage('check them again');
    await drainTurn();
    expect(
      llm.streamPrompts.any((p) => p.contains(mcpEmptyResultFragment())),
      isTrue,
    );
  });

  test('regen of an MCP turn re-calls the server', () async {
    final server = await _connectDocker();
    await chat.setActiveCharacter(card());
    await chat.setMcpServerEnabledForChat(server.id, true);
    await chat.sendMessage('are the containers up?');
    await drainTurn();
    expect(mcpCalls, 1);

    await chat.regenerateLastMessage();
    await drainTurn();
    expect(
      mcpCalls,
      greaterThan(1),
      reason: 'MCP re-calls; world may have changed',
    );
  });
}
