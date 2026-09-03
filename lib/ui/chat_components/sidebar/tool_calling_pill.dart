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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'sidebar_tokens.dart';

/// Sidebar pill answering "does my model support tool calling?" at a glance —
/// green when the model speaks the tools protocol, amber when it doesn't
/// (evals fall back to text mode; everything still works), neutral until
/// tested. Tapping retests against the live backend; verdicts also update
/// automatically as background passes probe and whenever the model or
/// backend is switched.
class ToolCallingPill extends StatelessWidget {
  final ChatService chatService;

  const ToolCallingPill({super.key, required this.chatService});

  @override
  Widget build(BuildContext context) {
    final testing = chatService.isTestingToolSupport;
    final support = chatService.toolCallSupport;
    final preferText = chatService.toolSupportJson['preferText'] == true;
    final paused = chatService.toolCallingPaused;

    final Color accent;
    final IconData icon;
    final String label;
    final String detail;
    if (testing) {
      accent = AppColors.porchHoneyOf(context);
      icon = Icons.build_circle_outlined;
      label = 'Tool calling: testing…';
      detail = 'Asking the model for a tool call';
    } else if (paused) {
      accent = AppColors.porchAmberOf(context);
      icon = Icons.pause_circle_outline;
      label = 'Tool calling: paused this run';
      detail = 'Empty answers this session — tap to retry';
    } else if (support == ToolCallSupport.supported && preferText) {
      accent = AppColors.porchAmberOf(context);
      icon = Icons.check_circle_outline;
      label = 'Tool calling: supported — using JSON';
      detail = 'You turned native tool calls off in Generation settings';
    } else {
      switch (support) {
        case ToolCallSupport.supported:
          accent = AppColors.bondHighOf(context);
          icon = Icons.check_circle;
          label = 'Tool calling: supported';
          detail = 'Realism, Journal & Growth use native tool calls';
        case ToolCallSupport.unsupported:
          accent = AppColors.taskAccentOf(context);
          icon = Icons.build_circle_outlined;
          label = 'Tool calling: not supported';
          detail = 'This model uses the text fallback — still works';
        case ToolCallSupport.untested:
          accent = AppColors.textTertiary(context);
          icon = Icons.help_outline;
          label = 'Tool calling: not tested';
          detail = 'Tap to test the current model';
      }
    }

    return Tooltip(
      message:
          'Whether the current model can answer engine evaluations '
          '(Realism, Journal, Growth Rings) with native tool calls. Models '
          'without tool calling automatically use a text fallback — chats '
          'still work, structured results are just a bit less reliable. '
          'Turn Native tool calling off under Generation settings to prefer '
          'JSON even when tools work. Tap to retest; retests also run '
          'automatically when you switch models or backends.',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
          onTap: testing ? null : () => chatService.testToolCalling(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: SidebarTokens.sectionGap),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                if (testing)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  Icon(icon, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.refresh,
                  size: 14,
                  color: AppColors.iconSecondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
