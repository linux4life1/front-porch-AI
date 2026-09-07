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
  McpHub? _orphanHub;

  McpHub get _hub {
    final live = _chat?.mcpHub;
    if (live != null) return live;
    return _orphanHub ??= McpHub(
      settings: _storage.mcpSettings,
      onNotify: () {},
    );
  }

  List<McpChatServerView> get _settingsViews {
    final chat = _chat;
    if (chat != null) return chat.mcpChatServers;
    return _hub.chatViews(enabledForChat: const {}, exclusions: const []);
  }

  Map<String, dynamic> settingsState() {
    final views = _settingsViews;
    return {
      'mcpDefault': _storage.mcpSettings.mcpDefault,
      'servers': [
        for (final v in views)
          {
            'id': v.id,
            'displayName': v.displayName,
            'url': v.url,
            'status': v.status.name,
            'lastError':
                mcpHumanizeConnectError(v.lastError, url: v.url).isEmpty
                ? v.lastError
                : mcpHumanizeConnectError(v.lastError, url: v.url),
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
    await _hub.connect(server.id);
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
      await _hub.connect(id);
    } else {
      await _hub.disconnect(id);
    }
    return settingsState();
  }

  Future<Map<String, dynamic>> removeServer(String id) async {
    await _storage.mcpSettings.removeServer(id);
    await _hub.onServerRemoved(id);
    return settingsState();
  }

  Future<Map<String, dynamic>> refreshServer(String id) async {
    await _hub.refresh(id);
    return settingsState();
  }

  Future<Map<String, dynamic>> checkServer(String id) async {
    final line = await _hub.check(id);
    final state = settingsState();
    state['checkResult'] = line;
    return state;
  }

  Future<Map<String, dynamic>> checkDraft(Map<String, dynamic> body) async {
    final url = body['url']?.toString() ?? '';
    String? line;
    String? used;
    for (final candidate in mcpSiblingUrls(url)) {
      line = await _hub.checkDraft(
        url: candidate,
        displayName: body['displayName']?.toString() ?? '',
        authToken: body['authToken']?.toString() ?? '',
      );
      used = candidate;
      if (line.startsWith('Connected')) break;
      if (line.contains('wants a token')) break;
    }
    if (line != null && line.startsWith('Connected') && used != null) {
      body['url'] = used;
      if ((body['displayName']?.toString() ?? '').trim().isEmpty) {
        body['displayName'] = mcpDefaultDisplayName(used);
      }
      await addServer(body);
    }
    final state = settingsState();
    state['checkResult'] =
        line ??
        mcpCheckResultLine(
          url: url,
          status: McpConnectionStatus.disconnected,
          toolNames: const [],
        );
    state['wantsToken'] = (line ?? '').contains('wants a token');
    return state;
  }

  Future<Map<String, dynamic>> findLocal() async {
    final result = await McpLocalProbe().findDocker();
    final state = settingsState();
    state['found'] = result.found;
    state['url'] = result.url;
    state['checkResult'] = result.message;
    return state;
  }

  Future<void> setChatEnabled(String id, bool enabled) async {
    await _chat?.setMcpServerEnabledForChat(id, enabled);
  }
}
