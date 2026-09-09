// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

Map<String, dynamic> _fn(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': name,
    'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
  },
};

List<String> _names(List<Map<String, dynamic>> tools) => [
  for (final t in tools) (t['function'] as Map)['name'] as String,
];

void main() {
  test(
    'changing the tools callback changes advertised names on the next generate',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_mcp_live_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      var catalog = <Map<String, dynamic>>[_fn('search_docs')];
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(calls: [], text: 'one'),
        const LlmToolResponse(calls: [], text: 'two'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mcpOptIn: true,
      );
      final harness = WaifuHarness(
        session: session,
        llm: llm,
        mcpOptIn: true,
        mcpToolsOf: () => catalog,
      );
      await harness.send('first');
      expect(_names(llm.calls.first.tools), contains('search_docs'));
      expect(_names(llm.calls.first.tools), isNot(contains('docker_ps')));

      catalog = [_fn('docker_ps')];
      await harness.send('second');
      expect(_names(llm.calls.last.tools), contains('docker_ps'));
      expect(_names(llm.calls.last.tools), isNot(contains('search_docs')));
    },
  );
}
