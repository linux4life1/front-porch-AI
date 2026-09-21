// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';

void main() {
  test('OpenCode mcp map is empty — chat MCP servers are gone', () {
    expect(openCodeMcpFromServers(const []), isEmpty);
    expect(waifuOpenCodeMcpMap(_FakeContext(), optIn: true), isEmpty);
  });
}

/// waifuOpenCodeMcpMap no longer reads Provider; context is unused.
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
