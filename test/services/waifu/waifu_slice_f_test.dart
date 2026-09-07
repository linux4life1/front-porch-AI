// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:http/http.dart' as http;

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_f_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('webfetch refuses redirects', () async {
    final fetch = WaifuWebFetch(
      sendRequest: (req) async => http.Response(
        'should-not-see',
        302,
        headers: {'location': 'https://evil.example/'},
      ),
    );
    final result = await fetch.get('https://example.com/doc');
    expect(result.ok, isFalse);
    expect(result.output.toLowerCase(), contains('redirect'));
    expect(result.output, isNot(contains('should-not-see')));
  });

  test('webfetch 200 is clipped and marked untrusted', () async {
    final fetch = WaifuWebFetch(
      maxBytes: 20,
      sendRequest: (req) async {
        expect(req.followRedirects, isFalse);
        return http.Response('abcdefghijklmnopqrstuvwxyz', 200);
      },
    );
    final result = await fetch.get('https://example.com/ok');
    expect(result.ok, isTrue);
    expect(result.output, contains('UNTRUSTED'));
    expect(result.output, contains('clipped'));
    expect(result.output.contains('z'), isFalse);
  });

  test('websearch uses the injected FP lookup', () async {
    var queries = <String>[];
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'web_search', arguments: {'query': 'porch lore'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Found it.'),
    ]);
    final harness = WaifuHarness(
      session: WaifuSession(
        folderRoot: root.path,
        coworker: _mira(),
        mode: WaifuMode.yolo,
      ),
      llm: llm,
      webSearch: (q) async {
        queries.add(q);
        return 'FP-SNIPPET';
      },
    );
    await harness.send('look it up');
    expect(queries, ['porch lore']);
    expect(llm.calls.last.prompt, contains('FP-SNIPPET'));
    expect(llm.calls.last.prompt, contains('UNTRUSTED'));
  });

  test('MCP tools are not advertised unless opted in', () async {
    final ping = {
      'type': 'function',
      'function': {
        'name': 'mcp_ping',
        'description': 'ping',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    };
    final llm = ScriptedWaifuLlm([const LlmToolResponse(calls: [], text: 'hi')]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    final off = WaifuHarness(
      session: session,
      llm: llm,
      mcpTools: [ping],
      mcpOptIn: false,
    );
    await off.send('hello');
    final namesOff = [
      for (final t in llm.calls.single.tools)
        (t['function'] as Map)['name'] as String,
    ];
    expect(namesOff, isNot(contains('mcp_ping')));
    expect(namesOff, contains('webfetch'));

    llm.calls.clear();
    final on = WaifuHarness(
      session: WaifuSession(
        folderRoot: root.path,
        coworker: _mira(),
        mode: WaifuMode.yolo,
      ),
      llm: llm,
      mcpTools: [ping],
      mcpOptIn: true,
      mcpCall: (name, args) async =>
          const WaifuToolResult(ok: true, output: 'pong'),
    );
    await on.send('hello');
    final namesOn = [
      for (final t in llm.calls.single.tools)
        (t['function'] as Map)['name'] as String,
    ];
    expect(namesOn, contains('mcp_ping'));
  });
}
