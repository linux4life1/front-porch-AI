// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stdio connect does not bypass the chat enable set or Plan/Build MCP gates.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';

import 'mcp_stdio_support.dart';

void main() {
  test(
    'stdio tools/call is a no-op when the server is not enabled for chat',
    () async {
      final settings = McpSettings()..initializeBase(null, () {});
      final server = await settings.addServer(
        displayName: 'Ping',
        transport: McpTransportKind.stdio,
        command: 'fake-mcp',
      );
      final hub = McpHub(
        settings: settings,
        onNotify: () {},
        openStdio: openPingStdio,
      );
      await hub.connect(server.id);
      expect(hub.clientFor(server.id)?.isConnected, isTrue);

      final blocked = await hub.callTool(
        serverId: server.id,
        toolName: 'ping',
        arguments: const {},
        enabledForChat: const {},
      );
      expect(blocked.ok, isFalse);
      expect(hub.callCount, 0);

      final allowed = await hub.callTool(
        serverId: server.id,
        toolName: 'ping',
        arguments: const {},
        enabledForChat: {server.id},
      );
      expect(allowed.ok, isTrue);
      expect(allowed.text, 'pong');
      expect(hub.callCount, 1);
    },
  );
}
