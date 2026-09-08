// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-tap Docker: reuse HTTP gateway, else spawn stdio, never leave a dead row.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/mcp/mcp.dart';

import 'mcp_stdio_support.dart';

int? _rpcId(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded['id'] as int?;
  } catch (_) {}
  return null;
}

http.Response _ok(int? id, Map<String, dynamic> result) {
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  test(
    'docker-easy reuses a listening HTTP gateway and does not spawn',
    () async {
      final settings = McpSettings()..initializeBase(null, () {});
      var spawned = 0;
      final hub = McpHub(
        settings: settings,
        onNotify: () {},
        sendRequest: (request) async {
          final body = request is http.Request ? request.body : '';
          final id = _rpcId(body);
          if (body.contains('"initialize"')) {
            return _ok(id, {'protocolVersion': '2025-03-26'});
          }
          if (body.contains('notifications/initialized')) {
            return http.Response('', 202);
          }
          if (body.contains('tools/list')) {
            return _ok(id, {
              'tools': [
                {'name': 'list_containers', 'inputSchema': <String, dynamic>{}},
              ],
            });
          }
          return http.Response('no', 404);
        },
        openStdio: (cfg) async {
          spawned++;
          throw StateError('must not spawn when HTTP is up');
        },
      );
      final probe = McpLocalProbe(get: (_) async => http.Response('ok', 200));
      final line = await McpDockerEasy.connect(
        settings: settings,
        hub: hub,
        probe: probe,
      );
      expect(line, startsWith('Connected'));
      expect(spawned, 0);
      expect(settings.servers, hasLength(1));
      expect(settings.servers.single.url, kMcpDockerMcpUrl);
      expect(settings.servers.single.isStdio, isFalse);
    },
  );

  test('docker-easy spawns stdio when nothing is listening on 8811', () async {
    final settings = McpSettings()..initializeBase(null, () {});
    final hub = McpHub(
      settings: settings,
      onNotify: () {},
      openStdio: openPingStdio,
    );
    final probe = McpLocalProbe(
      get: (_) async {
        throw Exception(
          'SocketException: Connection refused (OS Error: Connection refused)',
        );
      },
    );
    final line = await McpDockerEasy.connect(
      settings: settings,
      hub: hub,
      probe: probe,
    );
    expect(line, startsWith('Connected'));
    expect(settings.servers, hasLength(1));
    expect(settings.servers.single.isStdio, isTrue);
    expect(settings.servers.single.command, kMcpDockerStdioCommand);
    expect(settings.servers.single.args, kMcpDockerStdioArgs);
  });

  test('failed docker-easy stdio does not leave a dead Settings row', () async {
    final settings = McpSettings()..initializeBase(null, () {});
    final hub = McpHub(
      settings: settings,
      onNotify: () {},
      openStdio: (cfg) async => throw const ProcessException('docker', ['mcp']),
    );
    final probe = McpLocalProbe(
      get: (_) async => throw Exception('connection refused'),
    );
    final line = await McpDockerEasy.connect(
      settings: settings,
      hub: hub,
      probe: probe,
    );
    expect(line, isNot(startsWith('Connected')));
    expect(settings.servers, isEmpty);
  });

  test('stdio command + args survive prefs reload', () async {
    final settings = McpSettings()..initializeBase(null, () {});
    final server = await settings.addServer(
      displayName: 'Playwright',
      transport: McpTransportKind.stdio,
      command: 'npx',
      args: const ['-y', '@playwright/mcp'],
    );
    expect(server.isStdio, isTrue);
    final json = server.toJson();
    final reloaded = McpServerConfig.fromJson(json);
    expect(reloaded.transport, McpTransportKind.stdio);
    expect(reloaded.command, 'npx');
    expect(reloaded.args, ['-y', '@playwright/mcp']);
  });
}
