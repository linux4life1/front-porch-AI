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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/storage/settings/settings_base.dart';

/// Persisted MCP server list + the global "new chats enable MCP" default
/// (off) + per-chat enable sets keyed by session id.
///
/// Auth tokens live in the same prefs JSON as the URL. The macOS login
/// keychain prompts for the user password on every ad-hoc launch, which
/// made MCP unusable. Tavily stays in the keychain; a local Docker
/// bearer token is not that class of secret.
class McpSettings with SettingsBase {
  McpSettings();

  List<McpServerConfig> _servers = [];
  bool _mcpDefault = false;
  final Map<String, Set<String>> _chatEnabled = {};

  List<McpServerConfig> get servers => List.unmodifiable(_servers);
  bool get mcpDefault => _mcpDefault;

  McpServerConfig? serverById(String id) {
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Set<String> enabledForChat(String sessionId) =>
      Set<String>.from(_chatEnabled[sessionId] ?? const <String>{});

  Future<void> load() async {
    _mcpDefault = prefs?.getBool(k('mcp_default')) ?? false;
    final raw = prefs?.getString(k('mcp_servers')) ?? '[]';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _servers = [
          for (final item in decoded)
            if (item is Map)
              McpServerConfig.fromJson(Map<String, dynamic>.from(item)),
        ];
      }
    } catch (e) {
      debugPrint('[MCP] settings: server list parse failed: $e');
      _servers = [];
    }
    final chatsRaw = prefs?.getString(k('mcp_chat_enabled')) ?? '{}';
    try {
      final decoded = jsonDecode(chatsRaw);
      _chatEnabled.clear();
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (value is List) {
            _chatEnabled[key.toString()] = {
              for (final id in value) id.toString(),
            };
          }
        });
      }
    } catch (e) {
      debugPrint('[MCP] settings: chat enable map parse failed: $e');
    }
    final before = _servers.length;
    _dedupeGateways();
    if (_servers.length != before) await _persistServers();
    debugPrint(
      '[MCP] settings loaded: ${_servers.length} server(s), '
      'mcpDefault=$_mcpDefault, chats=${_chatEnabled.length}',
    );
  }

  /// One row per host:port (HTTP) or command+args (stdio). Prefers /mcp
  /// over a leftover /sse on the same gateway.
  void _dedupeGateways() {
    final byKey = <String, McpServerConfig>{};
    for (final s in _servers) {
      final key = mcpServerDedupeKey(s);
      final prev = byKey[key];
      if (prev == null) {
        byKey[key] = s;
        continue;
      }
      final preferNew = s.url.endsWith('/mcp') && !prev.url.endsWith('/mcp');
      byKey[key] = preferNew ? s : prev;
    }
    _servers = byKey.values.toList();
  }

  Future<void> setMcpDefault(bool value) async {
    _mcpDefault = value;
    await prefs?.setBool(k('mcp_default'), value);
    debugPrint('[MCP] settings mcpDefault=$value');
    notify();
  }

  Future<McpServerConfig> addServer({
    required String displayName,
    String url = '',
    Map<String, String> headers = const {},
    String authToken = '',
    bool enabledGlobal = true,
    McpTransportKind transport = McpTransportKind.http,
    String command = '',
    List<String> args = const [],
    Map<String, String> env = const {},
  }) async {
    final trimmedUrl = url.trim();
    final incoming = McpServerConfig(
      id: '_incoming',
      displayName: displayName,
      url: trimmedUrl,
      transport: transport == McpTransportKind.http && command.trim().isNotEmpty
          ? McpTransportKind.stdio
          : transport,
      command: command.trim(),
      args: args,
      env: env,
    );
    final key = mcpServerDedupeKey(incoming);
    final doomed = [
      for (final s in _servers)
        if (mcpServerDedupeKey(s) == key) s.id,
    ];
    for (final oldId in doomed) {
      await removeServer(oldId);
    }
    final id = 'mcp_${DateTime.now().microsecondsSinceEpoch}';
    final server = McpServerConfig(
      id: id,
      displayName: displayName.trim().isEmpty
          ? mcpDefaultDisplayName(trimmedUrl, command: command)
          : displayName.trim(),
      url: incoming.isStdio
          ? (trimmedUrl.isEmpty
                ? mcpStdioCommandLine(command, args)
                : trimmedUrl)
          : trimmedUrl,
      headers: Map<String, String>.from(headers),
      authToken: authToken.trim(),
      enabledGlobal: enabledGlobal,
      transport: incoming.transport,
      command: command.trim(),
      args: List<String>.from(args),
      env: Map<String, String>.from(env),
    );
    _servers = [..._servers, server];
    await _persistServers();
    debugPrint(
      '[MCP] settings add id=$id name="${server.displayName}" url=${server.url}',
    );
    notify();
    return server;
  }

  Future<void> updateServer(McpServerConfig updated) async {
    _servers = [
      for (final s in _servers)
        if (s.id == updated.id) updated else s,
    ];
    await _persistServers();
    debugPrint(
      '[MCP] settings update id=${updated.id} name="${updated.displayName}" '
      'enabledGlobal=${updated.enabledGlobal}',
    );
    notify();
  }

  Future<void> removeServer(String id) async {
    _servers = [
      for (final s in _servers)
        if (s.id != id) s,
    ];
    for (final entry in _chatEnabled.entries) {
      entry.value.remove(id);
    }
    await _persistServers();
    await _persistChatEnabled();
    debugPrint('[MCP] settings remove id=$id');
    notify();
  }

  Future<void> setEnabledForChat(String sessionId, Set<String> ids) async {
    _chatEnabled[sessionId] = Set<String>.from(ids);
    await _persistChatEnabled();
    debugPrint('[MCP] settings chat $sessionId enable=${ids.toList()}');
    notify();
  }

  Future<void> _persistServers() async {
    final payload = [for (final s in _servers) s.toJson()];
    await prefs?.setString(k('mcp_servers'), jsonEncode(payload));
  }

  Future<void> _persistChatEnabled() async {
    final payload = <String, List<String>>{
      for (final e in _chatEnabled.entries)
        if (e.value.isNotEmpty) e.key: e.value.toList(),
    };
    await prefs?.setString(k('mcp_chat_enabled'), jsonEncode(payload));
  }
}
