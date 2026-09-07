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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/waifu/waifu_context_bar.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_opt_in.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mode_bar.dart';
import 'package:front_porch_ai/ui/waifu/waifu_skills_panel.dart';
import 'package:front_porch_ai/ui/waifu/waifu_todo_list.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Waifu Coder right pane: portrait, Main Settings (model / temp / UI),
/// then harness info in the slot chat uses for realism. No journal, no
/// needs, no bond.
class WaifuSidebar extends StatelessWidget {
  const WaifuSidebar({
    super.key,
    required this.session,
    required this.portrait,
    required this.mcpOptIn,
    required this.onMcpOptIn,
    required this.onMode,
    this.onPreserveThinking,
    this.todos,
    this.mcpLine,
    this.skills,
    this.onSkillsChanged,
  });

  final WaifuSession session;
  final File? portrait;
  final bool mcpOptIn;
  final ValueChanged<bool> onMcpOptIn;
  final ValueChanged<WaifuMode> onMode;
  final ValueChanged<bool>? onPreserveThinking;
  final WaifuTodos? todos;
  final String? mcpLine;
  final WaifuSkillHub? skills;
  final VoidCallback? onSkillsChanged;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Container(
      key: const Key('waifu-sidebar'),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          left: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        children: [
          CharacterPortrait(file: portrait, size: 160, shrinkIfEmpty: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              session.coworker.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          ChatMainSettingsButton(
            key: const Key('waifu-main-settings'),
            onSelected: (value) => _openSettings(context, value),
            items: const [
              PopupMenuItem(
                value: 'chat',
                child: SettingsMenuItem(
                  icon: Icons.chat_bubble_outline,
                  label: 'Chat Settings',
                ),
              ),
              PopupMenuItem(
                value: 'model',
                child: SettingsMenuItem(
                  icon: Icons.memory_outlined,
                  label: 'Model Settings',
                ),
              ),
              PopupMenuItem(
                value: 'ui',
                child: SettingsMenuItem(
                  icon: Icons.tune_outlined,
                  label: 'UI Settings',
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WaifuContextBar(session: session),
                  if (skills != null) ...[
                    PorchAccordion(
                      id: 'waifu_skills',
                      emoji: '✨',
                      title: 'Skills',
                      subtitle: skills!.market.catalog.isEmpty
                          ? 'official catalog'
                          : '${skills!.market.catalog.length} official',
                      accent: amber,
                      initiallyExpanded: false,
                      child: WaifuSkillsPanel(
                        hub: skills!,
                        onChanged: onSkillsChanged,
                      ),
                    ),
                    const SizedBox(height: SidebarTokens.sectionGap),
                  ],
                  PorchAccordion(
                    id: 'waifu_harness',
                    emoji: '🛠️',
                    title: 'Harness',
                    subtitle: session.mode.name,
                    accent: amber,
                    initiallyExpanded: true,
                    child: WaifuModeBar(
                      mode: session.mode,
                      enabled: !session.running,
                      onChanged: onMode,
                      preserveThinking: session.preserveThinking,
                      onPreserveThinking: onPreserveThinking,
                    ),
                  ),
                  const SizedBox(height: SidebarTokens.sectionGap),
                  PorchAccordion(
                    id: 'waifu_mcp',
                    emoji: '🔌',
                    title: 'MCP',
                    subtitle: mcpLine ?? 'off',
                    accent: amber,
                    initiallyExpanded: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WaifuMcpOptIn(value: mcpOptIn, onChanged: onMcpOptIn),
                        if (mcpLine != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Text(
                              mcpLine!,
                              key: const Key('waifu-mcp-status'),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (todos != null && todos!.items.isNotEmpty) ...[
                    const SizedBox(height: SidebarTokens.sectionGap),
                    PorchAccordion(
                      id: 'waifu_todos',
                      emoji: '✅',
                      title: 'Tasks',
                      accent: amber,
                      initiallyExpanded: true,
                      child: WaifuTodoList(todos: todos!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context, String value) {
    switch (value) {
      case 'chat':
        showDialog<void>(
          context: context,
          builder: (_) =>
              ChatSettingsDialog(settings: session.genSettings, onSave: (_) {}),
        );
      case 'model':
        showDialog<void>(
          context: context,
          builder: (_) => const ModelSettingsDialog(),
        );
      case 'ui':
        showDialog<void>(
          context: context,
          builder: (_) => UiSettingsDialog(character: session.coworker),
        );
    }
  }
}

/// One line for the MCP accordion: connected servers and tool count.
String? waifuMcpStatusLine(BuildContext context) {
  try {
    final chat = Provider.of<ChatService>(context);
    final snaps = chat.mcpHub.snapshots();
    final connected = [
      for (final s in snaps)
        if (s.config.enabledGlobal && s.status == McpConnectionStatus.connected)
          s,
    ];
    if (connected.isEmpty) {
      final configured = [
        for (final s in snaps)
          if (s.config.enabledGlobal) s,
      ];
      if (configured.isEmpty) return 'No servers in Settings';
      return 'Not connected';
    }
    final names = <String>[
      for (final s in connected)
        for (final t in s.tools) t.name,
    ];
    final servers = connected.map((s) => s.config.displayName).join(', ');
    return '$servers — ${mcpToolsPhrase(names)}';
  } on ProviderNotFoundException {
    return null;
  }
}
