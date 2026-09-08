// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stdio JSON-RPC handshake, tools/call, and a real Process.start pin.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/mcp/mcp.dart';

import 'mcp_stdio_support.dart';

void main() {
  test('stdio connect + tools/call over pipes', () async {
    final client = McpClient(
      config: const McpServerConfig(
        id: 'stdio-1',
        displayName: 'Ping',
        url: '',
        transport: McpTransportKind.stdio,
        command: 'fake-mcp',
      ),
      openStdio: openPingStdio,
    );
    await client.connect();
    expect(client.status, McpConnectionStatus.connected);
    expect(client.tools.map((t) => t.name), ['ping']);
    final result = await client.callTool('ping', const {});
    expect(result.ok, isTrue);
    expect(result.text, 'pong');
    await client.disconnect();
  });

  test(
    'stdio handshake failure leaves the server contributing nothing',
    () async {
      final client = McpClient(
        config: const McpServerConfig(
          id: 'stdio-down',
          displayName: 'Down',
          url: '',
          transport: McpTransportKind.stdio,
          command: 'missing-bin',
        ),
        openStdio: (cfg) async => throw ProcessException(
          cfg.command,
          cfg.args,
          'No such file or directory',
        ),
      );
      await client.connect();
      expect(client.status, McpConnectionStatus.error);
      expect(client.tools, isEmpty);
      expect(client.lastError, contains('Command not found'));
    },
  );

  test('stdio spawn talks JSON-RPC to a real child process', () async {
    final dart = await _dartOnPath();
    if (dart == null) {
      markTestSkipped('dart is not on PATH');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('mcp_stdio_spawn_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final script = File('${dir.path}/echo_mcp.dart');
    await script.writeAsString(r'''
import 'dart:convert';
import 'dart:io';

void main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final msg = jsonDecode(line);
    if (msg is! Map) continue;
    final method = msg['method'];
    final id = msg['id'];
    if (method == 'initialize') {
      stdout.writeln(jsonEncode({'jsonrpc':'2.0','id':id,'result':{'protocolVersion':'2025-03-26'}}));
    } else if (method == 'tools/list') {
      stdout.writeln(jsonEncode({'jsonrpc':'2.0','id':id,'result':{'tools':[{'name':'ping','description':'Ping','inputSchema':{'type':'object','properties':{}}}]}}));
    } else if (method == 'tools/call') {
      stdout.writeln(jsonEncode({'jsonrpc':'2.0','id':id,'result':{'content':[{'type':'text','text':'pong'}]}}));
    }
  }
}
''');
    final client = McpClient(
      config: McpServerConfig(
        id: 'spawn-1',
        displayName: 'Echo',
        url: '',
        transport: McpTransportKind.stdio,
        command: dart,
        args: [script.path],
      ),
      openStdio: mcpSpawnStdio,
    );
    await client.connect();
    expect(client.status, McpConnectionStatus.connected);
    expect(client.tools.map((t) => t.name), ['ping']);
    final result = await client.callTool('ping', const {});
    expect(result.ok, isTrue);
    expect(result.text, 'pong');
    await client.disconnect();
  });
}

Future<String?> _dartOnPath() async {
  try {
    final result = await Process.run('dart', ['--version']);
    if (result.exitCode == 0) return 'dart';
  } catch (_) {}
  final exe = Platform.resolvedExecutable;
  if (exe.endsWith('dart') || exe.endsWith('dart.exe')) return exe;
  return null;
}
