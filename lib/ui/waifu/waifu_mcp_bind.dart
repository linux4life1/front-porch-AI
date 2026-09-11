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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';

/// Map Porch MCP catalog rows into isolated OpenCode `mcp` config.
/// OpenCode 1.18: `{ name: { type: local|remote, ... } }`.
Map<String, dynamic> openCodeMcpFromServers(Iterable<McpServerConfig> servers) {
  final mcp = <String, dynamic>{};
  for (final s in servers) {
    if (!s.enabledGlobal) continue;
    final name = _openCodeMcpName(s);
    if (s.isStdio) {
      final cmd = s.command.trim();
      if (cmd.isEmpty) continue;
      mcp[name] = {
        'type': 'local',
        'command': [cmd, ...s.args],
        'enabled': true,
        if (s.env.isNotEmpty) 'environment': s.env,
      };
    } else if (s.url.trim().isNotEmpty) {
      mcp[name] = {
        'type': 'remote',
        'url': s.url.trim(),
        'enabled': true,
        if (s.headers.isNotEmpty) 'headers': s.headers,
      };
    }
  }
  return mcp;
}

String _openCodeMcpName(McpServerConfig s) {
  final raw = s.displayName.trim().isEmpty ? s.id : s.displayName.trim();
  final slug = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? s.id : slug;
}

/// Enabled chat servers → OpenCode mcp map. Empty when opt-in is off.
Map<String, dynamic> waifuOpenCodeMcpMap(
  BuildContext context, {
  required bool optIn,
}) {
  if (!optIn) return const {};
  try {
    final storage = Provider.of<StorageService>(context, listen: false);
    ChatService? chat;
    try {
      chat = Provider.of<ChatService>(context, listen: false);
    } on ProviderNotFoundException {
      chat = null;
    }
    final enabled =
        chat?.mcpEnabledServerIds ??
        {for (final s in storage.mcpSettings.servers) s.id};
    return openCodeMcpFromServers(
      storage.mcpSettings.servers.where((s) => enabled.contains(s.id)),
    );
  } on ProviderNotFoundException {
    return const {};
  }
}
