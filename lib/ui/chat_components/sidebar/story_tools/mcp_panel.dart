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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../sidebar_tokens.dart';

/// Per-chat MCP server toggles. Hidden when no servers are configured, so
/// existing goldens stay unmoved.
class McpPanel extends StatelessWidget {
  const McpPanel({super.key, required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    final servers = chat.mcpChatServers;
    if (servers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.extension,
          label: 'MCP servers',
          accent: AppColors.porchAmberOf(context),
        ),
        const SizedBox(height: 4),
        Text(
          'Tools from a server only reach this chat when its switch is on.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 6),
        for (final s in servers) _row(context, s),
      ],
    );
  }

  Widget _row(BuildContext context, McpChatServerView s) {
    final status = switch (s.status) {
      McpConnectionStatus.connected => 'connected',
      McpConnectionStatus.error => 'error',
      McpConnectionStatus.connecting => 'connecting',
      McpConnectionStatus.disconnected => 'disconnected',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                Text(
                  '$status'
                  '${s.toolNames.isEmpty ? '' : ' · ${s.toolNames.join(', ')}'}'
                  '${s.conflictToolNames.isEmpty ? '' : ' · collision'}',
                  style: TextStyle(
                    fontSize: 10,
                    color: s.conflictToolNames.isEmpty
                        ? AppColors.textTertiary(context)
                        : AppColors.logError,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: Switch(
              value: s.enabledForChat,
              onChanged: s.enabledGlobal
                  ? (v) => chat.setMcpServerEnabledForChat(s.id, v)
                  : null,
              activeThumbColor: AppColors.formMasterAccent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
