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
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_opt_in.dart';

/// In-Waifu MCP manage surface: opt-in, Docker-easy connect, stdio command,
/// and the same per-server enable set character chat uses.
class WaifuMcpPanel extends StatefulWidget {
  const WaifuMcpPanel({
    super.key,
    required this.session,
    required this.mcpOptIn,
    required this.onMcpOptIn,
    this.mcpLine,
  });

  final WaifuSession session;
  final bool mcpOptIn;
  final ValueChanged<bool> onMcpOptIn;
  final String? mcpLine;

  @override
  State<WaifuMcpPanel> createState() => _WaifuMcpPanelState();
}

class _WaifuMcpPanelState extends State<WaifuMcpPanel> {
  final _command = TextEditingController();
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('waifu-mcp-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WaifuMcpOptIn(
          value: widget.mcpOptIn,
          pathMode: widget.session.pathMode,
          onChanged: widget.onMcpOptIn,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            kWaifuMcpOpenCodeHonesty,
            key: const Key('waifu-mcp-opencode-honesty'),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        if (widget.mcpLine != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.mcpLine!,
              key: const Key('waifu-mcp-status'),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ..._manage(context),
      ],
    );
  }

  List<Widget> _manage(BuildContext context) {
    ChatService? chat;
    StorageService? storage;
    try {
      chat = context.watch<ChatService>();
      storage = context.watch<StorageService>();
    } on ProviderNotFoundException {
      return const [];
    }
    final views = chat.mcpChatServers;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              key: const Key('waifu-mcp-docker'),
              label: const Text('Connect Docker MCP'),
              onPressed: _busy ? null : () => _docker(chat!, storage!),
              backgroundColor: AppColors.surfaceContainerOf(context),
              side: BorderSide(color: AppColors.borderOf(context)),
              labelStyle: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: TextField(
          key: const Key('waifu-mcp-command'),
          controller: _command,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'stdio command (npx -y @scope/mcp-server)',
            hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextButton(
          key: const Key('waifu-mcp-add-stdio'),
          onPressed: _busy ? null : () => _addStdio(chat!, storage!),
          child: Text(
            'Connect command',
            style: TextStyle(color: AppColors.porchAmberOf(context)),
          ),
        ),
      ),
      if (_result != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _result!,
            key: const Key('waifu-mcp-connect-result'),
            style: TextStyle(
              fontSize: 12,
              color: _result!.startsWith('Connected')
                  ? AppColors.textSecondary(context)
                  : AppColors.negativeAccentOf(context),
            ),
          ),
        ),
      for (final s in views) _row(context, chat, s),
    ];
  }

  Widget _row(BuildContext context, ChatService chat, McpChatServerView s) {
    final status = s.status.name;
    final kind = s.transport == McpTransportKind.stdio ? 'stdio' : 'http';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
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
                  '$kind · $status'
                  '${s.toolNames.isEmpty ? '' : ' · ${mcpToolsPhrase(s.toolNames)}'}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: Switch(
              key: Key('waifu-mcp-enable-${s.id}'),
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

  Future<void> _docker(ChatService chat, StorageService storage) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final line = await McpDockerEasy.connect(
        settings: storage.mcpSettings,
        hub: chat.mcpHub,
      );
      if (!mounted) return;
      if (line.startsWith('Connected')) {
        await _enableDocker(chat, storage);
      }
      if (mounted) setState(() => _result = line);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addStdio(ChatService chat, StorageService storage) async {
    final parts = mcpSplitStdioArgs(_command.text);
    if (parts.isEmpty) {
      setState(() => _result = 'Enter a command first');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final command = parts.first;
      final args = parts.length < 2 ? const <String>[] : parts.sublist(1);
      final line = await chat.mcpHub.checkDraft(
        url: '',
        transport: McpTransportKind.stdio,
        command: command,
        args: args,
      );
      if (!mounted) return;
      if (line.startsWith('Connected')) {
        final server = await storage.mcpSettings.addServer(
          displayName: mcpDefaultDisplayName('', command: command),
          transport: McpTransportKind.stdio,
          command: command,
          args: args,
        );
        await chat.mcpHub.check(server.id);
        await chat.setMcpServerEnabledForChat(server.id, true);
        _command.clear();
      }
      if (mounted) setState(() => _result = line);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableDocker(ChatService chat, StorageService storage) async {
    for (final s in storage.mcpSettings.servers) {
      if (mcpIsDockerConfig(s)) {
        await chat.setMcpServerEnabledForChat(s.id, true);
        return;
      }
    }
  }
}
