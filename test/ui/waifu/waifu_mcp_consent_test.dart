// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';

void main() {
  test('stdio and remote servers land in isolated OpenCode mcp config', () {
    const stdio = McpServerConfig(
      id: 's1',
      displayName: 'Docs Ping',
      url: '',
      transport: McpTransportKind.stdio,
      command: 'npx',
      args: ['-y', 'docs-mcp'],
    );
    const remote = McpServerConfig(
      id: 's2',
      displayName: 'Remote Docs',
      url: 'https://example.test/mcp',
    );
    const off = McpServerConfig(
      id: 's3',
      displayName: 'Off',
      url: 'https://off.test/mcp',
      enabledGlobal: false,
    );
    final mcp = openCodeMcpFromServers([stdio, remote, off]);
    expect(mcp.containsKey('off'), isFalse);
    expect(mcp['docs-ping'], {
      'type': 'local',
      'command': ['npx', '-y', 'docs-mcp'],
      'enabled': true,
    });
    expect(mcp['remote-docs'], {
      'type': 'remote',
      'url': 'https://example.test/mcp',
      'enabled': true,
    });
  });
}
