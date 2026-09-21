// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('idle estimate includes OpenCode tools and MCP schemas', () {
    final cardOnly = waifuOpenCodePromptEstimate(
      systemPrompt: 'x' * 40,
      speech: '',
    );
    final withMcp = waifuOpenCodePromptEstimate(
      systemPrompt: 'x' * 40,
      speech: '',
      mcpToolCount: 112,
    );
    expect(cardOnly, greaterThan(kWaifuOpenCodeNativeToolTokens));
    expect(withMcp - cardOnly, 112 * kWaifuMcpToolSchemaTokens);
  });

  test('oMLX does not use a 256k kcpps context window', () {
    expect(
      waifuResolveContextBudget(
        porchContextSize: 277518,
        apiUrl: 'http://localhost:8000/v1',
      ),
      40960,
    );
    expect(
      waifuResolveContextBudget(
        porchContextSize: 16384,
        apiUrl: 'http://localhost:8000/v1',
      ),
      16384,
    );
    expect(
      waifuResolveContextBudget(
        porchContextSize: 277518,
        apiUrl: 'https://nano-gpt.com/api/v1',
      ),
      277518,
    );
  });

  test('session.updated tokens become prompt+output', () {
    final events = parseOpenCodeSse(
      'data: {"type":"session.updated","properties":{"id":"ses_1","tokens":{"input":10200,"output":19,"reasoning":0,"cache":{"read":0,"write":0}}}}\n'
      '\n',
    );
    expect(events, hasLength(1));
    final t = events.single as OpenCodeSessionTokens;
    expect(t.promptTokens, 10200);
    expect(t.outputTokens, 19);
  });
}
