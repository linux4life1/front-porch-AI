// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _tool(String name, String description) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
  },
};

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_mcp_permissions_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  WaifuSession session(WaifuMode mode) => WaifuSession(
    folderRoot: root.path,
    coworker: CharacterCard(name: 'Iris'),
    mode: mode,
  );

  test(
    'Plan blocks mutating MCP, while read-only MCP remains useful',
    () async {
      var mutationCalls = 0;
      final mutateLlm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'create_issue', arguments: {'title': 'no'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'I kept it read-only.'),
      ]);
      final mutate = WaifuHarness(
        session: session(WaifuMode.plan),
        llm: mutateLlm,
        mcpTools: [_tool('create_issue', 'Create an issue')],
        mcpOptIn: true,
        mcpCall: (name, args) async {
          mutationCalls++;
          return const WaifuToolResult(ok: true, output: 'created');
        },
      );
      await mutate.send('make an issue');
      expect(mutationCalls, 0);
      expect(mutate.session.toolChips.single.ok, isFalse);

      var searchCalls = 0;
      final search = WaifuHarness(
        session: session(WaifuMode.plan),
        llm: ScriptedWaifuLlm([
          const LlmToolResponse(
            calls: [
              LlmToolCall(name: 'search_docs', arguments: {'query': 'API'}),
            ],
            text: '',
          ),
          const LlmToolResponse(calls: [], text: 'Found it.'),
        ]),
        mcpTools: [_tool('search_docs', 'Search documentation')],
        mcpOptIn: true,
        mcpCall: (name, args) async {
          searchCalls++;
          return const WaifuToolResult(ok: true, output: 'docs');
        },
      );
      await search.send('look it up');
      expect(searchCalls, 1);
      expect(search.session.toolChips.single.ok, isTrue);
    },
  );

  test('Build asks before a mutating MCP call', () async {
    var asks = 0;
    var calls = 0;
    final harness = WaifuHarness(
      session: session(WaifuMode.build),
      llm: ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'delete_item', arguments: {'id': '1'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'You said no.'),
      ]),
      mcpTools: [_tool('delete_item', 'Delete an item')],
      mcpOptIn: true,
      onAsk: (request) async {
        asks++;
        return WaifuAskDecision.deny;
      },
      mcpCall: (name, args) async {
        calls++;
        return const WaifuToolResult(ok: true, output: 'deleted');
      },
    );
    await harness.send('delete it');
    expect(asks, 1);
    expect(calls, 0);
  });

  test('built-in filesystem tools win an MCP name collision', () async {
    var mcpCalls = 0;
    final harness = WaifuHarness(
      session: session(WaifuMode.yolo),
      llm: ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'write',
              arguments: {'path': 'local.txt', 'contents': 'local'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Written locally.'),
      ]),
      mcpTools: [_tool('write', 'Remote write')],
      mcpOptIn: true,
      mcpCall: (name, args) async {
        mcpCalls++;
        return const WaifuToolResult(ok: true, output: 'remote');
      },
    );
    await harness.send('write locally');
    expect(mcpCalls, 0);
    expect(await File(p.join(root.path, 'local.txt')).readAsString(), 'local');
  });
}
