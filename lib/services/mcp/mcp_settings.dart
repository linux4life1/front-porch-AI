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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/storage/settings/settings_base.dart';

/// Persisted MCP server list + the global "new chats enable MCP" default
/// (off) + per-chat enable sets keyed by session id.
class McpSettings with SettingsBase {
  McpSettings({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

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
    for (var i = 0; i < _servers.length; i++) {
      final s = _servers[i];
      final token = await _readAuth(s.id);
      if (token.isNotEmpty) {
        _servers[i] = s.copyWith(authToken: token);
      }
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
    debugPrint(
      '[MCP] settings loaded: ${_servers.length} server(s), '
      'mcpDefault=$_mcpDefault, chats=${_chatEnabled.length}',
    );
  }

  Future<void> setMcpDefault(bool value) async {
    _mcpDefault = value;
    await prefs?.setBool(k('mcp_default'), value);
    debugPrint('[MCP] settings mcpDefault=$value');
    notify();
  }

  Future<McpServerConfig> addServer({
    required String displayName,
    required String url,
    Map<String, String> headers = const {},
    String authToken = '',
    bool enabledGlobal = true,
  }) async {
    final id = 'mcp_${DateTime.now().microsecondsSinceEpoch}';
    final server = McpServerConfig(
      id: id,
      displayName: displayName.trim().isEmpty ? url : displayName.trim(),
      url: url.trim(),
      headers: Map<String, String>.from(headers),
      authToken: authToken.trim(),
      enabledGlobal: enabledGlobal,
    );
    _servers = [..._servers, server];
    await _persistServers();
    await _writeAuth(id, server.authToken);
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
    await _writeAuth(updated.id, updated.authToken);
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
    await _writeAuth(id, '');
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

  Future<String> _readAuth(String id) async {
    try {
      return (await _secureStorage.read(key: k('mcp_auth_$id')))?.trim() ?? '';
    } catch (e) {
      debugPrint('[MCP] settings auth read failed for $id: $e');
      return '';
    }
  }

  Future<void> _writeAuth(String id, String token) async {
    final key = k('mcp_auth_$id');
    try {
      if (token.trim().isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: token.trim());
      }
    } catch (e) {
      debugPrint('[MCP] settings auth write failed for $id: $e');
    }
  }
}
