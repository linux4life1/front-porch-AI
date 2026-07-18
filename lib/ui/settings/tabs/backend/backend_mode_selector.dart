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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';

/// Backend-mode selector (Local KoboldCPP / OpenAI-compatible API / oMLX)
/// extracted from settings_page's Backend tab. Pure lift; reads LLMProvider +
/// BackendManager via Provider, switches the active backend, and shows the
/// per-mode blurb. AppColors exclusive.
class BackendModeSelector extends StatelessWidget {
  const BackendModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final backendManager = Provider.of<BackendManager>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final theme = Theme.of(context);
    final muted = AppColors.textTertiary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Backend Mode'),
        const SizedBox(height: 8),
        // Intel Mac warning banner.
        if (backendManager.isIntelMac) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.taskAccentOf(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.taskAccentOf(context).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: AppColors.taskAccentOf(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Local inference is not supported on Intel Macs. Only '
                    'Remote API mode is available.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.taskAccentOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<BackendType>(
                groupValue: llmProvider.activeBackend,
                onChanged: (val) async {
                  if (val != null) {
                    await llmProvider.setActiveBackend(val);
                    if (context.mounted) {
                      final message = switch (val) {
                        BackendType.kobold =>
                          'Switched to local KoboldCPP backend.',
                        BackendType.openRouter =>
                          'Switched to OpenAI-Compatible API backend.',
                        BackendType.omlx => 'Switched to oMLX backend.',
                      };
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    }
                  }
                },
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<BackendType>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              Icons.computer,
                              size: 18,
                              color: backendManager.isIntelMac
                                  ? muted
                                  : theme.iconTheme.color,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Local (KoboldCPP)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: backendManager.isIntelMac
                                      ? muted
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        value: BackendType.kobold,
                        enabled: !backendManager.isIntelMac,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<BackendType>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              Icons.cloud,
                              size: 18,
                              color: theme.iconTheme.color,
                            ),
                            const SizedBox(width: 6),
                            const Flexible(
                              child: Text(
                                'OpenAI-Compatible API',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        value: BackendType.openRouter,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<BackendType>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              Icons.apple,
                              size: 18,
                              color: Platform.isMacOS
                                  ? theme.iconTheme.color
                                  : muted,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'oMLX',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Platform.isMacOS ? null : muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        value: BackendType.omlx,
                        enabled: Platform.isMacOS,
                      ),
                    ),
                  ],
                ),
              ),
              if (llmProvider.activeBackend == BackendType.kobold)
                Text(
                  'Use a local KoboldCPP instance (optionally launched from a '
                  '.kcpps preset).',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                )
              else if (llmProvider.activeBackend == BackendType.omlx)
                Text(
                  'Local LLM inference via oMLX on Apple Silicon. Requires '
                  'oMLX running on port 8000.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                )
              else
                Text(
                  'Any OpenAI-compatible API — remote (OpenRouter, Nano-GPT) '
                  'or a local server (LM Studio, vLLM). Set the URL below.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
