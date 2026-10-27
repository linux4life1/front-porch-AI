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
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/tabs/voice_media_tab/voice_media_tab.dart';

export 'package:front_porch_ai/ui/settings/tabs/voice_media_tab/voice_media_tab.dart'
    show CallSystemPromptField;

/// Settings → Voice & Media. Shared drag state for the Voice Buffer slider
/// (dragCallBuffer) and the remote model list are owned by the settings page
/// and passed in. AppColors only for colors/surfaces/text/icons.
class VoiceMediaTab extends StatelessWidget {
  const VoiceMediaTab({
    super.key,
    this.dragCallBuffer,
    required this.onDragCallBufferChanged,
    required this.availableModels,
  });

  final double? dragCallBuffer;
  final void Function(double?) onDragCallBufferChanged;
  final List<RemoteModelInfo>
  availableModels; // typed for shared state from shell (smallest fix for loose/edge)

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    // Subscribed so the tab rebuilds when the model manager notifies.
    Provider.of<ModelManager>(context);
    final llmProvider = Provider.of<LLMProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TtsSection(storageService),
          VoiceMediaSttSection(
            storageService: storageService,
            llmProvider: llmProvider,
            availableModels: availableModels,
            dragCallBuffer: dragCallBuffer,
            onDragCallBufferChanged: onDragCallBufferChanged,
          ),

          // Self-hiding: renders nothing (header included) until the offline
          // vision helper is installed — the feature is offered only in chat.
          const PhotoUnderstandingCard(),

          const VoiceMediaExpressionSection(),

          const SizedBox(height: 24),
          const ImageGenEnableSection(),
          // Appears only while old-engine model files still sit on disk.
          const LegacyCleanupCard(),
        ],
      ),
    );
  }
}

/// Text-to-Speech section: engine name, enabled + active-voice subtitle, and
/// the Configure button that opens [TtsSettingsDialog].
class _TtsSection extends StatelessWidget {
  const _TtsSection(this.storageService);

  final StorageService storageService;

  static String _engineDisplayName(String engineId) {
    switch (engineId) {
      case 'kokoro':
        return 'Kokoro TTS';
      case 'openai':
        return 'OpenAI TTS';
      case 'piper':
        return 'Piper TTS';
      default:
        return 'TTS';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Text-to-Speech'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.volume_up,
                color: AppColors.porchAmberOf(context),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _engineDisplayName(storageService.ttsSettings.ttsEngine),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      storageService.ttsSettings.ttsEnabled
                          ? () {
                              final voiceKey =
                                  storageService.ttsSettings.ttsVoiceModel;
                              if (voiceKey.isEmpty) {
                                return 'Enabled — Voice: Not set';
                              }
                              final ttsService = Provider.of<TtsService>(
                                context,
                                listen: false,
                              );
                              final match = ttsService.activeVoices.where(
                                (v) => v.id == voiceKey,
                              );
                              final displayName = match.isNotEmpty
                                  ? match.first.name
                                  : voiceKey;
                              return 'Enabled — Voice: $displayName';
                            }()
                          : 'Disabled',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => TtsSettingsDialog(),
                ),
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Configure'),
                style: ElevatedButton.styleFrom(
                  // Warm-porch: was AppColors.userBubble (cool-blue chrome
                  // misuse of a chat-bubble constant); onAccentOf keeps
                  // the ink readable on the amber fill.
                  backgroundColor: AppColors.formAccentOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
        const AudioMissingNotice(),
      ],
    );
  }
}
