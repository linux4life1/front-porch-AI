// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stdio connect does not bypass the chat enable set or Plan/Build MCP gates.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

import 'mcp_stdio_support.dart';

Map<String, dynamic> _tool(String name, String description) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
  },
};

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

  test('Plan still blocks mutating MCP after a stdio-shaped catalog', () async {
    final root = await Directory.systemTemp.createTemp('waifu_stdio_perm_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    var mutationCalls = 0;
    final harness = WaifuHarness(
      session: WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.plan,
      ),
      llm: ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'create_issue', arguments: {'title': 'no'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'I kept it read-only.'),
      ]),
      mcpTools: [_tool('create_issue', 'Create an issue via stdio MCP')],
      mcpOptIn: true,
      mcpCall: (name, args) async {
        mutationCalls++;
        return const WaifuToolResult(ok: true, output: 'created');
      },
    );
    await harness.send('make an issue');
    expect(mutationCalls, 0);
    expect(
      harness.session.toolChips.any((c) => c.name == 'create_issue' && !c.ok),
      isTrue,
    );
    expect(await File(p.join(root.path, 'created')).exists(), isFalse);
  });
}
