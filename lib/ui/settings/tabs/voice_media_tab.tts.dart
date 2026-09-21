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

part of 'voice_media_tab.dart';

/// Text-to-Speech section of the Voice & Media tab: engine name, enabled +
/// active-voice subtitle, and the Configure button that opens
/// [TtsSettingsDialog]. Lifted verbatim from the pre-split god file.
extension _VoiceMediaTtsSection on VoiceMediaTab {
  String _engineDisplayName(String engineId) {
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

  Widget _buildTtsSection(BuildContext context, StorageService storageService) {
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
                  // misuse of a chat-bubble constant); onChaosAccent keeps
                  // the ink readable on the amber fill.
                  backgroundColor: AppColors.formMasterAccent,
                  foregroundColor: AppColors.onChaosAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
