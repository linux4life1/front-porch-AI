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
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

/// Host switcher for the Backend tab. Same one-row bar as Model Settings.
/// [config] is the chat URL/key/model stack — it stays in this card so
/// nothing (Side jobs, OpenCode) can wedge between chips and the key.
class BackendModeSelector extends StatelessWidget {
  const BackendModeSelector({
    super.key,
    required this.apiUrlController,
    required this.apiKeyController,
    this.config,
  });

  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final Widget? config;

  @override
  Widget build(BuildContext context) {
    final backendManager = Provider.of<BackendManager>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final storage = Provider.of<StorageService>(context);
    final theme = Theme.of(context);
    final muted = AppColors.textTertiary(context);
    final kind = resolveRemoteProviderKind(
      backendType: switch (llmProvider.activeBackend) {
        BackendType.kobold => 'kobold',
        BackendType.omlx => 'omlx',
        BackendType.openRouter => 'openRouter',
      },
      url: storage.backendSettings.remoteApiUrl,
    );

    return Column(
      key: const Key('chat-speech-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Chat speech'),
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
              RemoteProviderBar(
                selected: kind,
                showOmlx: Platform.isMacOS,
                koboldEnabled: !backendManager.isIntelMac,
                onSelected: (next) async {
                  await applyRemoteProvider(
                    kind: next,
                    storage: storage,
                    llm: llmProvider,
                    urlController: apiUrlController,
                    keyController: apiKeyController,
                  );
                },
              ),
              const SizedBox(height: 10),
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
              else if (kind == RemoteProviderKind.custom)
                Text(
                  'Any other OpenAI-compatible endpoint. Paste the URL below.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                )
              else
                Text(
                  'Named host — URL and last model restore on tap. Custom is '
                  'for a URL that is not OpenRouter, Nano-GPT, or LM Studio.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              if (config != null) ...[const SizedBox(height: 16), config!],
            ],
          ),
        ),
      ],
    );
  }
}
