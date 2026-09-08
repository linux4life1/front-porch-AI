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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Always-visible MCP server address + Check connection, under Porch Life.
///
/// Connecting is not consent — the Porch Life toggle only seeds new chats;
/// each chat still has its own sidebar switches.
class McpServersPanel extends StatefulWidget {
  const McpServersPanel({super.key, this.probe});

  /// Test seam for Find local servers.
  final McpLocalProbe? probe;

  @override
  State<McpServersPanel> createState() => _McpServersPanelState();
}

class _McpServersPanelState extends State<McpServersPanel> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _command = TextEditingController();
  bool _checking = false;
  bool _wantToken = false;
  String? _result;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _command.dispose();
    super.dispose();
  }

  Future<void> _fillDocker() async {
    _url.text = kMcpDockerMcpUrl;
    if (_name.text.trim().isEmpty) _name.text = 'Docker';
    setState(() => _result = null);
  }

  Future<void> _findLocal() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await (widget.probe ?? McpLocalProbe()).findDocker();
    if (!mounted) return;
    if (result.found && result.url != null) {
      _url.text = result.url!;
      if (_name.text.trim().isEmpty) _name.text = 'Docker';
    }
    setState(() {
      _checking = false;
      _result = result.message;
    });
  }

  Future<void> _connectDockerEasy() async {
    final storage = context.read<StorageService>();
    final chat = context.read<ChatService>();
    setState(() {
      _checking = true;
      _result = null;
    });
    final line = await McpDockerEasy.connect(
      settings: storage.mcpSettings,
      hub: chat.mcpHub,
      probe: widget.probe,
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = line;
    });
  }

  Future<void> _checkDraft() async {
    final commandLine = _command.text.trim();
    if (commandLine.isNotEmpty) {
      await _checkStdio(commandLine);
      return;
    }
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(
        () => _result = mcpCheckResultLine(
          url: '',
          status: McpConnectionStatus.disconnected,
          toolNames: const [],
        ),
      );
      return;
    }
    final storage = context.read<StorageService>();
    final chat = context.read<ChatService>();
    setState(() {
      _checking = true;
      _result = null;
    });
    String? line;
    String? used;
    for (final candidate in mcpSiblingUrls(url)) {
      line = await chat.mcpHub.checkDraft(
        url: candidate,
        displayName: _name.text,
        authToken: _token.text,
      );
      used = candidate;
      if (line.startsWith('Connected')) break;
      if (line.contains('wants a token')) {
        _wantToken = true;
        break;
      }
    }
    if (!mounted) return;
    if (line != null && line.startsWith('Connected') && used != null) {
      final server = await storage.mcpSettings.addServer(
        displayName: _name.text.trim(),
        url: used,
        authToken: _token.text.trim(),
      );
      await chat.mcpHub.check(server.id);
      _name.clear();
      _url.clear();
      _token.clear();
      _wantToken = false;
    }
    setState(() {
      _checking = false;
      _result = line;
    });
  }

  Future<void> _checkStdio(String commandLine) async {
    final parts = mcpSplitStdioArgs(commandLine);
    final command = parts.isEmpty ? '' : parts.first;
    final args = parts.length < 2 ? const <String>[] : parts.sublist(1);
    final storage = context.read<StorageService>();
    final chat = context.read<ChatService>();
    setState(() {
      _checking = true;
      _result = null;
    });
    final line = await chat.mcpHub.checkDraft(
      url: '',
      displayName: _name.text,
      transport: McpTransportKind.stdio,
      command: command,
      args: args,
    );
    if (!mounted) return;
    if (line.startsWith('Connected')) {
      final server = await storage.mcpSettings.addServer(
        displayName: _name.text.trim(),
        transport: McpTransportKind.stdio,
        command: command,
        args: args,
      );
      await chat.mcpHub.check(server.id);
      _name.clear();
      _command.clear();
    }
    setState(() {
      _checking = false;
      _result = line;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final chat = context.watch<ChatService>();
    final settings = storage.mcpSettings;
    final snaps = {for (final s in chat.mcpHub.snapshots()) s.config.id: s};

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect Docker MCP starts Docker Desktop’s toolkit on stdio — '
            'one tap, no URL. Or tap Docker, then Check, for the HTTP gateway. '
            'A token is only needed if the HTTP server asks.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                key: const Key('mcp-docker-stdio'),
                label: const Text('Connect Docker MCP'),
                onPressed: _checking ? null : _connectDockerEasy,
                backgroundColor: AppColors.surfaceContainerOf(context),
                side: BorderSide(color: AppColors.borderOf(context)),
                labelStyle: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
              ActionChip(
                key: const Key('mcp-docker-preset'),
                label: const Text('Docker'),
                onPressed: _checking ? null : _fillDocker,
                backgroundColor: AppColors.surfaceContainerOf(context),
                side: BorderSide(color: AppColors.borderOf(context)),
                labelStyle: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
              ActionChip(
                key: const Key('mcp-find-local'),
                label: const Text('Find local servers'),
                onPressed: _checking ? null : _findLocal,
                backgroundColor: AppColors.surfaceContainerOf(context),
                side: BorderSide(color: AppColors.borderOf(context)),
                labelStyle: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('mcp-add-url'),
            controller: _url,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Or paste a URL',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            ),
          ),
          TextField(
            key: const Key('mcp-add-command'),
            controller: _command,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Or a stdio command (npx -y @scope/mcp-server)',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            ),
          ),
          if (_wantToken)
            TextField(
              key: const Key('mcp-add-token'),
              controller: _token,
              obscureText: true,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Bearer token (printed when the gateway started)',
                hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('mcp-check-connection'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.porchAmberOf(context),
              foregroundColor: AppColors.onChaosAccent,
            ),
            onPressed: _checking ? null : _checkDraft,
            child: Text(_checking ? 'Checking…' : 'Check connection'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 6),
            Text(
              _result!,
              style: TextStyle(
                fontSize: 12,
                color: _result!.startsWith('Connected')
                    ? AppColors.textSecondary(context)
                    : AppColors.negativeAccentOf(context),
              ),
            ),
          ],
          for (final cfg in settings.servers)
            _ServerTile(
              config: cfg,
              snap: snaps[cfg.id],
              checking: _checking,
              onCheck: (line) => setState(() => _result = line),
            ),
        ],
      ),
    );
  }
}

class _ServerTile extends StatefulWidget {
  const _ServerTile({
    required this.config,
    required this.snap,
    required this.checking,
    required this.onCheck,
  });

  final McpServerConfig config;
  final McpServerSnapshot? snap;
  final bool checking;
  final ValueChanged<String> onCheck;

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  late final TextEditingController _url;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.config.url);
  }

  @override
  void didUpdateWidget(covariant _ServerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.url != widget.config.url &&
        _url.text.trim() != widget.config.url) {
      _url.text = widget.config.url;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _persistUrl() async {
    final next = _url.text.trim();
    if (next.isEmpty || next == widget.config.url) return;
    await context.read<StorageService>().mcpSettings.updateServer(
      widget.config.copyWith(url: next),
    );
  }

  Future<void> _check() async {
    await _persistUrl();
    final line = await context.read<ChatService>().mcpHub.check(
      widget.config.id,
    );
    if (!mounted) return;
    widget.onCheck(line);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    final chat = context.read<ChatService>();
    final status = widget.snap?.status ?? McpConnectionStatus.disconnected;
    final tools = widget.snap?.tools ?? const [];
    final error = mcpHumanizeConnectError(
      widget.snap?.lastError,
      url: widget.config.url,
    );
    final title = widget.config.displayName.startsWith('http')
        ? mcpDefaultDisplayName(widget.config.url)
        : widget.config.displayName;
    final statusColor = switch (status) {
      McpConnectionStatus.connected => AppColors.porchAmberOf(context),
      McpConnectionStatus.error => AppColors.logError,
      McpConnectionStatus.connecting => AppColors.textSecondary(context),
      McpConnectionStatus.disconnected => AppColors.textTertiary(context),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              Switch(
                value: widget.config.enabledGlobal,
                onChanged: (v) async {
                  await storage.mcpSettings.updateServer(
                    widget.config.copyWith(enabledGlobal: v),
                  );
                  if (v) {
                    await chat.mcpHub.connect(widget.config.id);
                  } else {
                    await chat.mcpHub.disconnect(widget.config.id);
                  }
                },
                activeThumbColor: AppColors.formMasterAccent,
              ),
            ],
          ),
          TextField(
            key: Key('mcp-url-${widget.config.id}'),
            controller: _url,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'URL (Streamable HTTP or SSE)',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            ),
            onSubmitted: (_) => _persistUrl(),
          ),
          const SizedBox(height: 4),
          Text(
            error.isNotEmpty ? error : status.name,
            style: TextStyle(fontSize: 11, color: statusColor),
          ),
          if (tools.isNotEmpty)
            Text(
              mcpToolsPhrase([for (final t in tools) t.name]),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          Row(
            children: [
              TextButton(
                key: Key('mcp-check-${widget.config.id}'),
                onPressed: widget.checking ? null : _check,
                child: Text(
                  'Check connection',
                  style: TextStyle(color: AppColors.porchAmberOf(context)),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await storage.mcpSettings.removeServer(widget.config.id);
                  await chat.mcpHub.onServerRemoved(widget.config.id);
                },
                child: const Text(
                  'Remove',
                  style: TextStyle(color: AppColors.logError),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
