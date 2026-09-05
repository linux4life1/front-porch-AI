// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Catalog filtering, collision (first-connected wins), and flat OpenAI
// payload shape. Proven red: drop the enabledForChat filter → disabled
// server's tools appear; swap connectOrder → the other name wins.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/mcp/mcp.dart';

McpServerSnapshot _snap({
  required String id,
  required String name,
  required int order,
  List<String> tools = const [],
  McpConnectionStatus status = McpConnectionStatus.connected,
}) {
  return McpServerSnapshot(
    config: McpServerConfig(id: id, displayName: name, url: 'http://$id'),
    status: status,
    connectOrder: order,
    tools: [
      for (final t in tools)
        McpToolDef(
          name: t,
          description: '$t from $name',
          inputSchema: const {'type': 'object', 'properties': {}},
        ),
    ],
  );
}

void main() {
  test(
    'tools/list results appear only when the server is enabled for the chat',
    () {
      final catalog = buildMcpCatalog(
        inProcess: [inProcessWebSearchTool()],
        servers: [
          _snap(
            id: 'docker',
            name: 'Docker',
            order: 1,
            tools: ['list_containers'],
          ),
        ],
        enabledForChat: const {},
      );
      expect(catalog.lookup('list_containers'), isNull);
      expect(catalog.lookup(kWebSearchToolName), isNotNull);
    },
  );

  test('enabled + connected server tools join the catalog', () {
    final catalog = buildMcpCatalog(
      inProcess: [inProcessWebSearchTool()],
      servers: [
        _snap(
          id: 'docker',
          name: 'Docker',
          order: 1,
          tools: ['list_containers'],
        ),
      ],
      enabledForChat: {'docker'},
    );
    expect(catalog.lookup('list_containers'), isNotNull);
    expect(catalog.lookup('list_containers')!.source, McpToolSource.mcp);
    expect(catalog.lookup('list_containers')!.serverDisplayName, 'Docker');
  });

  test('disconnected server contributes nothing even if enabled', () {
    final catalog = buildMcpCatalog(
      inProcess: const [],
      servers: [
        _snap(
          id: 'docker',
          name: 'Docker',
          order: 1,
          tools: ['list_containers'],
          status: McpConnectionStatus.error,
        ),
      ],
      enabledForChat: {'docker'},
    );
    expect(catalog.tools, isEmpty);
  });

  test(
    'unified catalog is flat: no source prefix in the payload the model sees',
    () {
      final catalog = buildMcpCatalog(
        inProcess: [inProcessWebSearchTool()],
        servers: [
          _snap(
            id: 'docker',
            name: 'Docker',
            order: 1,
            tools: ['list_containers'],
          ),
        ],
        enabledForChat: {'docker'},
      );
      final payload = catalog.toOpenAiTools();
      final names = [
        for (final t in payload) (t['function'] as Map)['name'] as String,
      ];
      expect(names, ['web_search', 'list_containers']);
      expect(jsonEncodeSafe(payload), isNot(contains('docker__')));
      expect(jsonEncodeSafe(payload), isNot(contains('via MCP')));
      expect(jsonEncodeSafe(payload), isNot(contains('in-process')));
    },
  );

  test(
    'collision: first connected wins, the other is omitted with a warning',
    () {
      final catalog = buildMcpCatalog(
        inProcess: const [],
        servers: [
          _snap(id: 'a', name: 'Alpha', order: 1, tools: ['ping']),
          _snap(id: 'b', name: 'Beta', order: 2, tools: ['ping']),
        ],
        enabledForChat: {'a', 'b'},
      );
      expect(catalog.tools, hasLength(1));
      expect(catalog.tools.single.serverId, 'a');
      expect(catalog.exclusions, hasLength(1));
      expect(catalog.exclusions.single.serverId, 'b');
      expect(catalog.exclusions.single.reason, contains('first-connected'));
    },
  );

  test('in-process name wins over an MCP server advertising the same name', () {
    final catalog = buildMcpCatalog(
      inProcess: [inProcessWebSearchTool()],
      servers: [
        _snap(id: 'x', name: 'X', order: 1, tools: ['web_search']),
      ],
      enabledForChat: {'x'},
    );
    expect(catalog.lookup('web_search')!.source, McpToolSource.inProcess);
    expect(catalog.exclusions.single.toolName, 'web_search');
  });

  test(
    'shouldAdvertiseMcp is off for Continue, autonomous, guests, empty set',
    () {
      expect(
        shouldAdvertiseMcp(
          enabledServerIds: {'a'},
          continueMode: true,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseMcp(
          enabledServerIds: {'a'},
          continueMode: false,
          toolsUnsupported: false,
          autonomousMode: true,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseMcp(
          enabledServerIds: {'a'},
          continueMode: false,
          toolsUnsupported: false,
          guestTurn: true,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseMcp(
          enabledServerIds: const [],
          continueMode: false,
          toolsUnsupported: false,
        ),
        isFalse,
      );
      expect(
        shouldAdvertiseMcp(
          enabledServerIds: {'a'},
          continueMode: false,
          toolsUnsupported: false,
        ),
        isTrue,
      );
    },
  );
}

String jsonEncodeSafe(Object o) => o.toString();
