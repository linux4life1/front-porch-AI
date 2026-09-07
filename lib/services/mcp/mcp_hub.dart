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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/mcp/mcp_client.dart';
import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/mcp/mcp_settings.dart';

/// Owns one [McpClient] per configured server. Connect order is the
/// collision tie-break: first successful connect wins the tool name.
class McpHub {
  McpHub({required this.settings, required this.onNotify, this.sendRequest});

  final McpSettings settings;
  final VoidCallback onNotify;

  /// Test seam forwarded to every client.
  Future<http.Response> Function(http.BaseRequest request)? sendRequest;

  final Map<String, McpClient> _clients = {};
  int _connectSeq = 0;
  int callCount = 0;

  List<McpServerSnapshot> snapshots() {
    return [for (final cfg in settings.servers) _snapshot(cfg)];
  }

  McpClient? clientFor(String serverId) => _clients[serverId];

  McpServerSnapshot _snapshot(McpServerConfig cfg) {
    final client = _clients[cfg.id];
    return McpServerSnapshot(
      config: cfg,
      status: client?.status ?? McpConnectionStatus.disconnected,
      connectOrder: client?.connectOrder ?? 1 << 30,
      lastError: client?.lastError,
      tools: client?.tools ?? const [],
    );
  }

  List<McpChatServerView> chatViews({
    required Set<String> enabledForChat,
    required List<CatalogExclusion> exclusions,
  }) {
    final conflictsByServer = <String, List<String>>{};
    for (final e in exclusions) {
      conflictsByServer.putIfAbsent(e.serverId, () => []).add(e.toolName);
    }
    return [
      for (final snap in snapshots())
        McpChatServerView(
          id: snap.config.id,
          displayName: snap.config.displayName,
          url: snap.config.url,
          status: snap.status,
          enabledForChat: enabledForChat.contains(snap.config.id),
          enabledGlobal: snap.config.enabledGlobal,
          lastError: snap.lastError,
          toolNames: [for (final t in snap.tools) t.name],
          conflictToolNames: conflictsByServer[snap.config.id] ?? const [],
        ),
    ];
  }

  Future<void> connect(String id) async {
    final cfg = settings.serverById(id);
    if (cfg == null) {
      debugPrint('[MCP] hub connect skipped — unknown id=$id');
      return;
    }
    if (!cfg.enabledGlobal) {
      debugPrint(
        '[MCP] hub connect skipped — "${cfg.displayName}" disabled globally',
      );
      await disconnect(id);
      return;
    }
    await _handshake(cfg);
    onNotify();
  }

  static const draftId = '_mcp_draft';

  /// Handshake a URL without saving a server. Failed checks must not leave
  /// a dead row in Settings.
  Future<String> checkDraft({
    required String url,
    String displayName = '',
    String authToken = '',
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return mcpCheckResultLine(
        url: '',
        status: McpConnectionStatus.disconnected,
        toolNames: const [],
      );
    }
    final cfg = McpServerConfig(
      id: draftId,
      displayName: displayName.trim().isEmpty
          ? mcpDefaultDisplayName(trimmed)
          : displayName.trim(),
      url: trimmed,
      authToken: authToken.trim(),
      enabledGlobal: false,
    );
    debugPrint('[MCP] hub checkDraft url=$trimmed');
    await _handshake(cfg);
    onNotify();
    final client = _clients[draftId];
    final line = mcpCheckResultLine(
      url: trimmed,
      status: client?.status ?? McpConnectionStatus.error,
      toolNames: [for (final t in client?.tools ?? const []) t.name],
      lastError: client?.lastError,
    );
    await disconnect(draftId);
    return line;
  }

  /// Handshake + tools/list for Settings. Checking is not consent — the
  /// global switch may stay off; the catalog still requires the chat toggle.
  Future<String> check(String id) async {
    final cfg = settings.serverById(id);
    if (cfg == null) {
      return mcpCheckResultLine(
        url: '',
        status: McpConnectionStatus.error,
        toolNames: const [],
      );
    }
    debugPrint('[MCP] hub check id=$id url=${cfg.url}');
    await _handshake(cfg);
    onNotify();
    final client = _clients[id];
    return mcpCheckResultLine(
      url: cfg.url,
      status: client?.status ?? McpConnectionStatus.error,
      toolNames: [for (final t in client?.tools ?? const []) t.name],
      lastError: client?.lastError,
    );
  }

  Future<void> _handshake(McpServerConfig cfg) async {
    final existing = _clients[cfg.id];
    final client = existing ?? McpClient(config: cfg, sendRequest: sendRequest);
    client
      ..config = cfg
      ..sendRequest = sendRequest;
    if (existing == null) {
      client.connectOrder = ++_connectSeq;
      _clients[cfg.id] = client;
    }
    await client.connect();
  }

  Future<void> refresh(String id) async {
    debugPrint('[MCP] hub refresh id=$id');
    await connect(id);
  }

  Future<void> disconnect(String id) async {
    final client = _clients.remove(id);
    if (client != null) await client.disconnect();
    onNotify();
  }

  Future<void> onServerRemoved(String id) async {
    await disconnect(id);
  }

  /// Security: a call to a server that is not in [enabledForChat] is a
  /// no-op — no `tools/call` on the wire.
  Future<McpCallResult> callTool({
    required String serverId,
    required String toolName,
    required Map<String, dynamic> arguments,
    required Set<String> enabledForChat,
  }) async {
    if (!enabledForChat.contains(serverId)) {
      debugPrint(
        '[MCP] tools/call NO-OP tool=$toolName server=$serverId '
        '(not enabled for this chat)',
      );
      return const McpCallResult(ok: false, text: '', isError: true);
    }
    final client = _clients[serverId];
    if (client == null || !client.isConnected) {
      debugPrint(
        '[MCP] tools/call NO-OP tool=$toolName server=$serverId '
        '(not connected)',
      );
      return const McpCallResult(ok: false, text: '', isError: true);
    }
    callCount++;
    return client.callTool(toolName, arguments);
  }
}
