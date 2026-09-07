// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Socket dumps and 401s must read as instructions, not errno 61.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/mcp/mcp.dart';

void main() {
  test('connection refused on 8811 tells you Docker is not listening', () {
    const dumped =
        'ClientException with SocketException: Connection refused '
        '(OS Error: Connection refused, errno = 61), '
        'address = 127.0.0.1, port = 53641, '
        'uri=http://127.0.0.1:8811/sse';
    expect(
      mcpCheckResultLine(
        url: 'http://127.0.0.1:8811/sse',
        status: McpConnectionStatus.error,
        toolNames: const [],
        lastError: dumped,
      ),
      contains('Nothing is listening'),
    );
    expect(
      mcpCheckResultLine(
        url: 'http://127.0.0.1:8811/sse',
        status: McpConnectionStatus.error,
        toolNames: const [],
        lastError: dumped,
      ),
      isNot(contains('ClientException')),
    );
    expect(
      mcpCheckResultLine(
        url: 'http://127.0.0.1:8811/sse',
        status: McpConnectionStatus.error,
        toolNames: const [],
        lastError: dumped,
      ),
      contains('docker mcp gateway run'),
    );
  });

  test('401 asks for the printed Bearer token, not a mystery Auth field', () {
    final line = mcpCheckResultLine(
      url: 'http://127.0.0.1:8811/mcp',
      status: McpConnectionStatus.error,
      toolNames: const [],
      lastError: 'HTTP 401',
    );
    expect(line, contains('token'));
    expect(line.toLowerCase(), contains('bearer'));
  });

  test(
    'sibling URLs try /mcp and /sse without the user picking a transport',
    () {
      expect(mcpSiblingUrls('http://127.0.0.1:8811/mcp'), [
        'http://127.0.0.1:8811/mcp',
        'http://127.0.0.1:8811/sse',
      ]);
      expect(mcpSiblingUrls('http://127.0.0.1:8811/sse'), [
        'http://127.0.0.1:8811/sse',
        'http://127.0.0.1:8811/mcp',
      ]);
    },
  );

  test('a huge tool list is a count, not a wall of names', () {
    final names = [for (var i = 0; i < 110; i++) 'tool_$i'];
    final line = mcpCheckResultLine(
      url: kMcpDockerMcpUrl,
      status: McpConnectionStatus.connected,
      toolNames: names,
    );
    expect(line, 'Connected — 110 tools');
    expect(line, isNot(contains('tool_0')));
    expect(mcpToolsPhrase(names), '110 tools');
  });

  test(
    'empty display name is Docker for the local gateway, never the raw URL',
    () {
      expect(mcpDefaultDisplayName('http://127.0.0.1:8811/sse'), 'Docker');
      expect(
        mcpDefaultDisplayName('http://127.0.0.1:3000/mcp'),
        isNot(contains('http')),
      );
    },
  );
}
