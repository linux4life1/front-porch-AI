// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared library tools/ cards become an OpenCode remote MCP map.
// Empty drawer stays empty. Execute still rides executeUserToolCard.
//
// Proven red: the old waifuOpenCodeMcpMap stub always returned {}.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';

void main() {
  late Directory root;
  late PorchToolsMcpHost host;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_waifu_mcp_');
    host = PorchToolsMcpHost();
  });

  tearDown(() async {
    await host.stop();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Directory toolsDir() => Directory('${root.path}/tools');

  Future<void> writeCard({
    String name = 'search_neokosmos',
    String filename = 'neokosmos.json',
    bool enabled = true,
  }) async {
    final dir = toolsDir();
    await dir.create(recursive: true);
    await File('${dir.path}/$filename').writeAsString(
      jsonEncode({
        'name': name,
        'description': 'Look up Neokosmos canon.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['query'],
        },
        'method': 'POST',
        'url': 'https://example.invalid/search',
        'enabled': enabled,
      }),
    );
  }

  test('opt-in with loaded cards writes a remote loopback mcp map', () async {
    await writeCard();
    final map = await buildPorchToolsMcpMap(
      optIn: true,
      toolsDir: toolsDir(),
      host: host,
    );
    expect(map, isNotEmpty);
    final entry = map[kPorchToolsMcpName] as Map<String, dynamic>;
    expect(entry['type'], 'remote');
    expect(entry['enabled'], isTrue);
    expect(entry['oauth'], isFalse);
    final url = Uri.parse(entry['url'] as String);
    expect(url.host, '127.0.0.1');
    expect(url.path, '/mcp');
    expect((entry['headers'] as Map)['Authorization'], startsWith('Bearer '));
  });

  test('empty tools/ or opt-in off stays an empty mcp map', () async {
    expect(
      await buildPorchToolsMcpMap(
        optIn: true,
        toolsDir: toolsDir(),
        host: host,
      ),
      isEmpty,
    );
    await writeCard();
    expect(
      await buildPorchToolsMcpMap(
        optIn: false,
        toolsDir: toolsDir(),
        host: host,
      ),
      isEmpty,
    );
    expect(
      await waifuOpenCodeMcpMap(
        null,
        optIn: true,
        toolsDir: toolsDir(),
        host: host,
      ),
      isNotEmpty,
    );
    expect(openCodeMcpFromServers(const []), isEmpty);
  });

  test(
    'tools/list skips disabled cards; tools/call uses execute path',
    () async {
      await writeCard();
      await writeCard(name: 'off_tool', filename: 'off.json', enabled: false);
      final listed = handlePorchToolsMcpRpc({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      }, toolsDir: toolsDir());
      final tools = (listed['result'] as Map)['tools'] as List;
      expect(tools.map((t) => (t as Map)['name']), ['search_neokosmos']);

      String? postedBody;
      final called = await handlePorchToolsMcpRpcAsync(
        {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'search_neokosmos',
            'arguments': {'query': 'Rhea'},
          },
        },
        toolsDir: toolsDir(),
        send:
            ({
              required method,
              required url,
              required headers,
              required body,
            }) async {
              postedBody = body;
              return const UserToolHttpResult(
                ok: true,
                text: 'Rhea keeps the lantern.',
              );
            },
      );
      expect(jsonDecode(postedBody!), {
        'tool': 'search_neokosmos',
        'arguments': {'query': 'Rhea'},
      });
      final result = called['result'] as Map;
      expect(result['isError'], isFalse);
      expect(
        ((result['content'] as List).first as Map)['text'],
        contains('lantern'),
      );
    },
  );
}
