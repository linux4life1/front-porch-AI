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

part of '../chat_service.dart';

/// MCP hub builder + per-chat enable set. Global default is off; the four
/// seed sites call [_seedMcpForFreshChat]. Load restores the saved set.
extension ChatServiceMcp on ChatService {
  McpHub _buildMcpHub() {
    final hub = McpHub(
      settings: _storageService.mcpSettings,
      onNotify: notifyListeners,
    );
    for (final s in _storageService.mcpSettings.servers) {
      if (s.enabledGlobal) unawaited(hub.connect(s.id));
    }
    return hub;
  }

  List<McpChatServerView> get _mcpChatServersImpl {
    final catalog = buildMcpCatalog(
      inProcess: const [],
      servers: _mcpHub.snapshots(),
      enabledForChat: _mcpEnabledServerIds,
    );
    return _mcpHub.chatViews(
      enabledForChat: _mcpEnabledServerIds,
      exclusions: catalog.exclusions,
    );
  }

  void _seedMcpForFreshChat() {
    _mcpEnabledServerIds = {};
    if (_storageService.mcpSettings.mcpDefault) {
      _mcpEnabledServerIds = {
        for (final s in _storageService.mcpSettings.servers)
          if (s.enabledGlobal) s.id,
      };
    }
    for (final id in _mcpEnabledServerIds) {
      unawaited(_mcpHub.connect(id));
    }
    debugPrint(
      '[MCP] seed chat enable set=${_mcpEnabledServerIds.toList()} '
      'mcpDefault=${_storageService.mcpSettings.mcpDefault}',
    );
  }

  void _restoreMcpForSession(String sessionId) {
    _mcpEnabledServerIds = _storageService.mcpSettings.enabledForChat(
      sessionId,
    );
    for (final id in _mcpEnabledServerIds) {
      unawaited(_mcpHub.connect(id));
    }
    debugPrint(
      '[MCP] restore session=$sessionId enable=${_mcpEnabledServerIds.toList()}',
    );
  }

  Future<void> _setMcpServerEnabledForChatImpl(String id, bool enabled) async {
    if (enabled) {
      _mcpEnabledServerIds = {..._mcpEnabledServerIds, id};
      unawaited(_mcpHub.connect(id));
    } else {
      _mcpEnabledServerIds = {
        for (final s in _mcpEnabledServerIds)
          if (s != id) s,
      };
    }
    final sid = _currentSessionId;
    if (sid != null) {
      await _storageService.mcpSettings.setEnabledForChat(
        sid,
        _mcpEnabledServerIds,
      );
    }
    debugPrint(
      '[MCP] chat toggle server=$id enabled=$enabled '
      'set=${_mcpEnabledServerIds.toList()}',
    );
    notifyListeners();
  }
}
