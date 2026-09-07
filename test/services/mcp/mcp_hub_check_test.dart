// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hub.check handshakes even when the server is globally off — checking
// is not consent to advertise tools.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('check reports tools without requiring the global switch', () async {
    final settings = McpSettings()..initializeBase(null, () {});
    final server = await settings.addServer(
      displayName: 'Docker',
      url: 'http://127.0.0.1:3000/mcp',
      enabledGlobal: false,
    );
    final hub = McpHub(settings: settings, onNotify: () {});
    hub.sendRequest = (request) async {
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
      return http.Response('no', 404);
    };

    final line = await hub.check(server.id);
    expect(line, 'Connected — 1 tool: list_containers');
    expect(settings.serverById(server.id)!.enabledGlobal, isFalse);
  });
}
