// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/mcp/mcp.dart';

void main() {
  test(
    'disabled server: a model call is a no-op (no tools/call on the wire)',
    () async {
      final settings = McpSettings()..initializeBase(null, () {});
      final hub = McpHub(settings: settings, onNotify: () {});
      var httpCalls = 0;
      hub.sendRequest = (request) async {
        httpCalls++;
        return http.Response('{}', 200);
      };
      final result = await hub.callTool(
        serverId: 'docker',
        toolName: 'list_containers',
        arguments: const {},
        enabledForChat: const {},
      );
      expect(httpCalls, 0, reason: 'disabled server must not hit the wire');
      expect(result.ok, isFalse);
      expect(hub.callCount, 0);
    },
  );
}
