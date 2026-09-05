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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

/// Settings tab: connected MCP servers, status, tool inventory, add/remove.
class McpTab extends StatelessWidget {
  const McpTab({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final chat = context.watch<ChatService>();
    unawaited(chat.mcpHub.connectAllEnabled());
    final settings = storage.mcpSettings;
    final views = chat.mcpChatServers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FeatureGroupCard(
          title: 'MCP servers',
          subtitle: 'the character can use tools from servers you connect',
          rows: [
            FeatureRow(
              icon: Icons.extension_outlined,
              label: 'Enable for new chats',
              need: FeatureNeed.alone,
              blurb:
                  'Connecting a server is not consent to advertise its tools. '
                  'Each chat has its own switches in the sidebar. This only '
                  'seeds new chats with every globally-enabled server turned '
                  'on. Off by default.',
              value: settings.mcpDefault,
              onChanged: settings.setMcpDefault,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Servers',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addServer(context),
              icon: Icon(
                Icons.add,
                size: 16,
                color: AppColors.porchAmberOf(context),
              ),
              label: Text(
                'Add server',
                style: TextStyle(color: AppColors.porchAmberOf(context)),
              ),
            ),
          ],
        ),
        if (settings.servers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No servers yet. Add a Streamable HTTP or SSE URL. Front Porch '
              'does not spawn servers — you run them, we connect.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        for (final view in views) _ServerCard(view: view),
      ],
    );
  }

  Future<void> _addServer(BuildContext context) async {
    final result = await showDialog<_ServerDraft>(
      context: context,
      builder: (ctx) => const _ServerEditorDialog(),
    );
    if (result == null || !context.mounted) return;
    final storage = context.read<StorageService>();
    final chat = context.read<ChatService>();
    final server = await storage.mcpSettings.addServer(
      displayName: result.name,
      url: result.url,
      headers: result.headers,
      authToken: result.authToken,
    );
    await chat.mcpHub.connect(server.id);
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.view});

  final McpChatServerView view;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatService>();
    final storage = context.read<StorageService>();
    final statusColor = switch (view.status) {
      McpConnectionStatus.connected => AppColors.porchAmberOf(context),
      McpConnectionStatus.error => AppColors.logError,
      McpConnectionStatus.connecting => AppColors.textSecondary(context),
      McpConnectionStatus.disconnected => AppColors.textTertiary(context),
    };
    return Card(
      color: AppColors.cardOf(context),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    view.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                Switch(
                  value: view.enabledGlobal,
                  onChanged: (v) async {
                    final cfg = storage.mcpSettings.serverById(view.id);
                    if (cfg == null) return;
                    await storage.mcpSettings.updateServer(
                      cfg.copyWith(enabledGlobal: v),
                    );
                    if (v) {
                      await chat.mcpHub.connect(view.id);
                    } else {
                      await chat.mcpHub.disconnect(view.id);
                    }
                  },
                  activeThumbColor: AppColors.formMasterAccent,
                ),
              ],
            ),
            Text(
              view.url,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              view.status.name +
                  (view.lastError != null ? ' — ${view.lastError}' : ''),
              style: TextStyle(fontSize: 11, color: statusColor),
            ),
            if (view.toolNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Tools: ${view.toolNames.join(', ')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            if (view.conflictToolNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Name collision — omitted: ${view.conflictToolNames.join(', ')}. '
                  'Disable one server. Names are not auto-prefixed.',
                  style: TextStyle(fontSize: 11, color: AppColors.logError),
                ),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: () => chat.mcpHub.refresh(view.id),
                  child: Text(
                    'Refresh',
                    style: TextStyle(color: AppColors.porchAmberOf(context)),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await storage.mcpSettings.removeServer(view.id);
                    await chat.mcpHub.onServerRemoved(view.id);
                  },
                  child: Text(
                    'Remove',
                    style: const TextStyle(color: AppColors.logError),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerDraft {
  const _ServerDraft({
    required this.name,
    required this.url,
    required this.headers,
    required this.authToken,
  });
  final String name;
  final String url;
  final Map<String, String> headers;
  final String authToken;
}

class _ServerEditorDialog extends StatefulWidget {
  const _ServerEditorDialog();

  @override
  State<_ServerEditorDialog> createState() => _ServerEditorDialogState();
}

class _ServerEditorDialogState extends State<_ServerEditorDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _headerName = TextEditingController();
  final _headerValue = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _headerName.dispose();
    _headerValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'Add MCP server',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL (Streamable HTTP or SSE)',
              ),
            ),
            TextField(
              controller: _token,
              decoration: const InputDecoration(
                labelText: 'Auth token (optional)',
              ),
              obscureText: true,
            ),
            TextField(
              controller: _headerName,
              decoration: const InputDecoration(
                labelText: 'Extra header name (optional)',
              ),
            ),
            TextField(
              controller: _headerValue,
              decoration: const InputDecoration(
                labelText: 'Extra header value',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        TextButton(
          onPressed: () {
            final url = _url.text.trim();
            if (url.isEmpty) return;
            final headers = <String, String>{};
            final hn = _headerName.text.trim();
            if (hn.isNotEmpty) headers[hn] = _headerValue.text.trim();
            Navigator.pop(
              context,
              _ServerDraft(
                name: _name.text.trim(),
                url: url,
                headers: headers,
                authToken: _token.text.trim(),
              ),
            );
          },
          child: Text(
            'Add',
            style: TextStyle(color: AppColors.porchAmberOf(context)),
          ),
        ),
      ],
    );
  }
}
