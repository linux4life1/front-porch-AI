// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('loop prompt tells her to search unknown Flutter/Dart versions', () {
    final prompt = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Iris',
      transcript: const [],
      todos: '',
      mentionBlock: '',
      toolTrace: '',
    );
    expect(prompt, contains(kWaifuLookupCue));
    expect(prompt, contains('web_search'));
    expect(prompt, contains(kWaifuBuiltinsCue));
    expect(prompt, contains('2 bounded task layer(s) remain'));
  });

  test('MCP names land in the loop prompt when opted in', () {
    final line = waifuMcpToolsLine([
      {
        'type': 'function',
        'function': {'name': 'brave_search', 'description': 'Search the web'},
      },
      {
        'type': 'function',
        'function': {'name': 'mcp_ping', 'description': 'ping'},
      },
    ]);
    expect(line, contains('brave_search'));
    expect(line, contains('1 other MCP'));
    expect(line, isNot(contains('mcp_ping')));
    final prompt = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Iris',
      transcript: const [],
      todos: '',
      mentionBlock: '',
      toolTrace: '',
      mcpBlock: line,
    );
    expect(prompt, contains('brave_search'));
  });

  test('search-like MCP tools are advertised before other MCP tools', () {
    Map<String, dynamic> fn(String name, String desc) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': desc,
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    };
    final tools = waifuAdvertisedTools(
      exploreOnly: false,
      includeWebSearch: true,
      mcpOptIn: true,
      mcpTools: [
        fn('mcp_ping', 'ping'),
        fn('brave_search', 'Search the web'),
        fn('web_search', 'duplicate that must drop'),
      ],
      includeTask: false,
    );
    final names = [
      for (final t in tools) (t['function'] as Map)['name'] as String,
    ];
    expect(names.where((n) => n == 'web_search'), hasLength(1));
    expect(names, contains('webfetch'));
    expect(
      names.indexOf('web_search'),
      lessThan(names.indexOf('brave_search')),
    );
    expect(names.indexOf('brave_search'), lessThan(names.indexOf('mcp_ping')));
  });

  test('WaifuPage binds ChatService lookup as webSearch', () {
    final src = File('lib/ui/waifu/waifu_page.dart').readAsStringSync();
    expect(src, contains('waifuWebSearchBind'));
    expect(src, contains('webSearch: webSearch'));
  });
}
