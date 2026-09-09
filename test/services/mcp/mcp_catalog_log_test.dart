// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: 110 Docker tools printed one "catalog include" line each
// plus a names=[] dump, on every Waifu MCP panel rebuild.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/mcp/mcp.dart';

McpServerSnapshot _snap(List<String> tools) {
  return McpServerSnapshot(
    config: const McpServerConfig(
      id: 'docker',
      displayName: 'Docker',
      url: 'http://docker',
    ),
    status: McpConnectionStatus.connected,
    connectOrder: 1,
    tools: [
      for (final t in tools)
        McpToolDef(
          name: t,
          description: t,
          inputSchema: const {'type': 'object', 'properties': {}},
        ),
    ],
  );
}

void main() {
  test('catalog rebuild logs one summary, not one line per tool', () {
    final names = [for (var i = 0; i < 40; i++) 'tool_$i'];
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = original);

    final servers = [_snap(names)];
    buildMcpCatalog(
      inProcess: const [],
      servers: servers,
      enabledForChat: const {'docker'},
    );
    buildMcpCatalog(
      inProcess: const [],
      servers: servers,
      enabledForChat: const {'docker'},
    );

    final includes = logs.where((l) => l.contains('catalog include'));
    final built = logs.where((l) => l.contains('catalog built')).toList();
    expect(includes, isEmpty);
    expect(built, hasLength(1));
    expect(built.single, contains('40 tool(s)'));
    expect(built.single, isNot(contains('names=')));
    expect(built.single, isNot(contains('tool_0')));
  });
}
