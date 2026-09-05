// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Streamable HTTP handshake, tools/list, tools/call, and the no-stdio pin.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/mcp/mcp.dart';

int? _rpcId(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded['id'] as int?;
  } catch (_) {}
  return null;
}

void main() {
  test('connect + tools/list caches advertised tools', () async {
    final client = McpClient(
      config: const McpServerConfig(
        id: 's1',
        displayName: 'Docker',
        url: 'http://127.0.0.1:9/mcp',
      ),
      sendRequest: (request) async {
        final body = request is http.Request ? request.body : '';
        final rpcId = _rpcId(body);
        if (body.contains('"initialize"')) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': rpcId,
              'result': {'protocolVersion': '2025-03-26'},
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'mcp-session-id': 'sess-1',
            },
          );
        }
        if (body.contains('notifications/initialized')) {
          return http.Response('', 202);
        }
        if (body.contains('tools/list')) {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': rpcId,
              'result': {
                'tools': [
                  {
                    'name': 'list_containers',
                    'description': 'List Docker containers',
                    'inputSchema': {'type': 'object', 'properties': {}},
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('unexpected', 500);
      },
    );
    await client.connect();
    expect(client.status, McpConnectionStatus.connected);
    expect(client.tools.map((t) => t.name), ['list_containers']);
    expect(client.sessionId, 'sess-1');
  });

  test('tools/call returns concatenated text content', () async {
    final client = McpClient(
      config: const McpServerConfig(
        id: 's1',
        displayName: 'Docker',
        url: 'http://127.0.0.1:9/mcp',
      ),
      sendRequest: (request) async {
        final body = request is http.Request ? request.body : '';
        final rpcId = _rpcId(body);
        if (body.contains('"initialize"')) {
          return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': rpcId, 'result': {}}),
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
              'id': rpcId,
              'result': {
                'tools': [
                  {'name': 'list_containers', 'inputSchema': {}},
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
              'id': rpcId,
              'result': {
                'content': [
                  {'type': 'text', 'text': 'web is healthy'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('no', 404);
      },
    );
    await client.connect();
    final result = await client.callTool('list_containers', const {});
    expect(result.ok, isTrue);
    expect(result.text, 'web is healthy');
  });

  test('handshake failure leaves the server contributing nothing', () async {
    final client = McpClient(
      config: const McpServerConfig(
        id: 's1',
        displayName: 'Down',
        url: 'http://127.0.0.1:9/mcp',
      ),
      sendRequest: (request) async => http.Response('nope', 500),
    );
    await client.connect();
    expect(client.status, McpConnectionStatus.error);
    expect(client.tools, isEmpty);
  });

  test('no stdio spawn / no sidecar process in the client', () {
    for (final path in [
      'lib/services/mcp/mcp_client.dart',
      'lib/services/mcp/mcp_hub.dart',
      'lib/services/mcp/mcp_transport.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('Process.start')));
      expect(src, isNot(contains('Process.run')));
      expect(src, isNot(contains("import 'dart:io'")));
    }
  });

  test('SSE data frames parse into JSON-RPC messages', () {
    const body =
        'event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"ok":true}}\n\n';
    final msgs = parseSseJsonRpc(body);
    expect(msgs, hasLength(1));
    expect(msgs.first['id'], 1);
    expect((msgs.first['result'] as Map)['ok'], true);
  });
}
