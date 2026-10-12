// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';

void main() {
  testWidgets('OpenCode mcp map is empty — chat MCP servers are gone', (
    tester,
  ) async {
    expect(openCodeMcpFromServers(const []), isEmpty);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    );
    // No StorageService in this tree, so there is no tools folder to read.
    expect(await waifuOpenCodeMcpMap(context, optIn: true), isEmpty);
  });
}
