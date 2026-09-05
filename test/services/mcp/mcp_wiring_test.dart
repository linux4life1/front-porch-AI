// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Source-site pins for MCP v2. Default off; four seed sites; Continue skip.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/mcp/mcp.dart';

void main() {
  test('MCP default is off', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = McpSettings();
    s.initializeBase(null, () {});
    await s.load();
    expect(s.mcpDefault, isFalse);
    expect(s.servers, isEmpty);
  });

  test('all four seed sites read the per-chat enable set', () {
    const sites = {
      'lib/services/chat/chat_service_chat_entry.dart': 'opening a 1:1 chat',
      'lib/services/chat/chat_service_session_manage.dart': 'a fresh session',
      'lib/services/chat/chat_service_group_entry.dart': 'entering a group',
      'lib/services/chat/chat_service_import_seed.dart': 'import seed',
    };
    for (final e in sites.entries) {
      final src = File(e.key).readAsStringSync();
      expect(
        src,
        contains('_seedMcpForFreshChat'),
        reason: '${e.key} must seed the per-chat MCP enable set (${e.value})',
      );
    }
  });

  test('Continue does not call MCP', () {
    final request = File(
      'lib/services/chat/chat_service_generation_request.dart',
    ).readAsStringSync();
    expect(request, contains('shouldAdvertiseMcp'));
    expect(
      request,
      contains('continueMode: t.mode == GenerationMode.continue_'),
    );
    expect(request, contains('runCatalogRound'));
  });

  test('catalog is a list, not a forked search-only path', () {
    final request = File(
      'lib/services/chat/chat_service_generation_request.dart',
    ).readAsStringSync();
    expect(request, contains('buildMcpCatalog'));
    expect(request, contains('inProcessWebSearchTool()'));
    expect(request, contains('shouldAdvertiseWebSearch'));
  });
}
