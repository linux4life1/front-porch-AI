// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared stdio MCP pipe double for unit tests.

import 'dart:async';
import 'dart:convert';

import 'package:front_porch_ai/services/mcp/mcp.dart';

Future<McpStdioSession> openScriptedStdio(
  void Function(
    Map<String, dynamic> msg,
    void Function(Map<String, dynamic>) reply,
  )
  onMsg,
) async {
  final toClient = StreamController<List<int>>();
  final fromClient = StreamController<List<int>>();
  fromClient.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.trim().isEmpty) return;
        final msg = jsonDecode(line);
        if (msg is! Map) return;
        onMsg(Map<String, dynamic>.from(msg), (reply) {
          toClient.add(utf8.encode('${jsonEncode(reply)}\n'));
        });
      });
  return McpStdioSession(
    stdout: toClient.stream,
    write: fromClient.add,
    kill: () {
      unawaited(toClient.close());
      unawaited(fromClient.close());
    },
  );
}

Future<McpStdioSession> openPingStdio(McpServerConfig config) {
  return openScriptedStdio((msg, reply) {
    final method = msg['method']?.toString();
    final id = msg['id'];
    if (method == 'initialize') {
      reply({
        'jsonrpc': '2.0',
        'id': id,
        'result': {'protocolVersion': '2025-03-26'},
      });
    } else if (method == 'tools/list') {
      reply({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'tools': [
            {
              'name': 'ping',
              'description': 'Ping',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
            },
          ],
        },
      });
    } else if (method == 'tools/call') {
      reply({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {'type': 'text', 'text': 'pong'},
          ],
        },
      });
    }
  });
}
