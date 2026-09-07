// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

class _McpChat extends ChangeNotifier implements ChatService {
  _McpChat(this._hub, this._enabled);

  final McpHub _hub;
  final Set<String> _enabled;

  @override
  McpHub get mcpHub => _hub;

  @override
  Set<String> get mcpEnabledServerIds => _enabled;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int? _rpcId(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded['id'] as int?;
  } catch (_) {}
  return null;
}

void main() {
  testWidgets(
    'Waifu MCP requires the character-chat server enable set as well as opt-in',
    (tester) async {
      final settings = McpSettings();
      settings.initializeBase(null, () {});
      final server = await settings.addServer(
        displayName: 'Docs',
        url: 'http://127.0.0.1:9/mcp',
      );
      final hub = McpHub(settings: settings, onNotify: () {});
      hub.sendRequest = (request) async {
        final body = request is http.Request ? request.body : '';
        final id = _rpcId(body);
        if (body.contains('"initialize"')) {
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': {}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (body.contains('notifications/initialized')) {
          return http.Response('', 202);
        }
        if (body.contains('tools/list')) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'tools': [
                  {
                    'name': 'search_docs',
                    'description': 'Search docs',
                    'inputSchema': {
                      'type': 'object',
                      'properties': <String, dynamic>{},
                    },
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (body.contains('tools/call')) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'content': [
                  {'type': 'text', 'text': 'found'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unexpected', 500);
      };
      await hub.connect(server.id);

      late ({List<Map<String, dynamic>> tools, WaifuMcpCallFn? call}) binding;
      Future<void> pumpWith(Set<String> enabled) {
        return tester.pumpWidget(
          ChangeNotifierProvider<ChatService>.value(
            value: _McpChat(hub, enabled),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  binding = waifuMcpBind(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
      }

      await pumpWith(<String>{});
      expect(binding.tools, isEmpty);
      expect(hub.callCount, 0);

      await pumpWith({server.id});
      expect(
        binding.tools.map((tool) => (tool['function'] as Map)['name']),
        contains('search_docs'),
      );
      final result = await binding.call!('search_docs', const {});
      expect(result.ok, isTrue);
      expect(hub.callCount, 1);
    },
  );
}
