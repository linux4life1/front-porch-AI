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

import 'package:front_porch_ai/services/services.dart';

/// Settings list + per-chat enable set. Thin over [McpSettings] / [McpHub].
class McpFacade {
  McpFacade(this._storage, this._chat);

  final StorageService _storage;
  final ChatService? _chat;

  Map<String, dynamic> settingsState() {
    final views = _chat?.mcpChatServers ?? const <McpChatServerView>[];
    return {
      'mcpDefault': _storage.mcpSettings.mcpDefault,
      'servers': [
        for (final v in views)
          {
            'id': v.id,
            'displayName': v.displayName,
            'url': v.url,
            'status': v.status.name,
            'lastError': v.lastError,
            'enabledGlobal': v.enabledGlobal,
            'toolNames': v.toolNames,
            'conflictToolNames': v.conflictToolNames,
          },
      ],
    };
  }

  Map<String, dynamic> chatBlock() {
    final views = _chat?.mcpChatServers ?? const <McpChatServerView>[];
    return {
      'servers': [
        for (final v in views)
          {
            'id': v.id,
            'displayName': v.displayName,
            'status': v.status.name,
            'enabled': v.enabledForChat,
            'enabledGlobal': v.enabledGlobal,
            'toolNames': v.toolNames,
            'conflictToolNames': v.conflictToolNames,
          },
      ],
    };
  }

  Future<void> setMcpDefault(bool value) =>
      _storage.mcpSettings.setMcpDefault(value);

  Future<Map<String, dynamic>> addServer(Map<String, dynamic> body) async {
    final headers = <String, String>{};
    final raw = body['headers'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v != null) headers[k] = v.toString();
      });
    }
    final server = await _storage.mcpSettings.addServer(
      displayName: body['displayName']?.toString() ?? '',
      url: body['url']?.toString() ?? '',
      headers: headers,
      authToken: body['authToken']?.toString() ?? '',
      enabledGlobal: body['enabledGlobal'] != false,
    );
    await _chat?.mcpHub.connect(server.id);
    return settingsState();
  }

  Future<Map<String, dynamic>> updateServer(
    String id,
    Map<String, dynamic> body,
  ) async {
    final cfg = _storage.mcpSettings.serverById(id);
    if (cfg == null) return settingsState();
    final headers = body['headers'];
    final updated = cfg.copyWith(
      displayName: body['displayName']?.toString(),
      url: body['url']?.toString(),
      headers: headers is Map
          ? {
              for (final e in headers.entries)
                e.key.toString(): e.value.toString(),
            }
          : null,
      authToken: body['authToken']?.toString(),
      enabledGlobal: body['enabledGlobal'] is bool
          ? body['enabledGlobal'] as bool
          : null,
    );
    await _storage.mcpSettings.updateServer(updated);
    if (updated.enabledGlobal) {
      await _chat?.mcpHub.connect(id);
    } else {
      await _chat?.mcpHub.disconnect(id);
    }
    return settingsState();
  }

  Future<Map<String, dynamic>> removeServer(String id) async {
    await _storage.mcpSettings.removeServer(id);
    await _chat?.mcpHub.onServerRemoved(id);
    return settingsState();
  }

  Future<Map<String, dynamic>> refreshServer(String id) async {
    await _chat?.mcpHub.refresh(id);
    return settingsState();
  }

  Future<void> setChatEnabled(String id, bool enabled) async {
    await _chat?.setMcpServerEnabledForChat(id, enabled);
  }
}
