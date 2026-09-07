// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Plain-language Check connection lines. The Settings button is only useful
// if a non-developer can read pass vs fail without opening a log.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/mcp/mcp.dart';

void main() {
  test('empty URL asks for an address instead of pretending to connect', () {
    expect(
      mcpCheckResultLine(
        url: '  ',
        status: McpConnectionStatus.disconnected,
        toolNames: const [],
      ),
      'Enter a server address first',
    );
  });

  test('successful handshake lists the advertised tools', () {
    expect(
      mcpCheckResultLine(
        url: 'http://127.0.0.1:3000/mcp',
        status: McpConnectionStatus.connected,
        toolNames: const ['list_containers', 'logs'],
      ),
      'Connected — 2 tools: list_containers, logs',
    );
  });

  test('successful handshake with one tool uses the singular', () {
    expect(
      mcpCheckResultLine(
        url: 'http://127.0.0.1:3000/mcp',
        status: McpConnectionStatus.connected,
        toolNames: const ['list_containers'],
      ),
      'Connected — 1 tool: list_containers',
    );
  });

  test('handshake failure names the URL and the reason', () {
    expect(
      mcpCheckResultLine(
        url: 'http://127.0.0.1:9/mcp',
        status: McpConnectionStatus.error,
        toolNames: const [],
        lastError: 'HTTP 500',
      ),
      'Could not reach http://127.0.0.1:9/mcp — HTTP 500',
    );
  });
}
