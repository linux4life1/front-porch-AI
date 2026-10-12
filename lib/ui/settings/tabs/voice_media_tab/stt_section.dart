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
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/tabs/voice_media_tab/voice_call_settings.dart';

/// Voice Input (STT) section of the Voice & Media tab: enable switch,
/// Whisper model dropdown, download-progress + verified-on-disk row, the
/// microphone picker, and the Voice Call sub-block.
///
/// CRITICAL SEAM (do not re-split): the `if
/// (storageService.sttSettings.sttEnabled) ...[` conditional spread below wraps BOTH
/// this section's own controls AND the entire Voice Call sub-block
/// ([voiceCallSettingsChildren]) inside ONE Container. The conditional must
/// stay owned by this section — the voice-call widgets are spliced in with
/// `...` so the Container and its single sttEnabled gate are unchanged.
class VoiceMediaSttSection extends StatelessWidget {
  const VoiceMediaSttSection({
    super.key,
    required this.storageService,
    required this.llmProvider,
    required this.availableModels,
    required this.dragCallBuffer,
    required this.onDragCallBufferChanged,
  });

  final StorageService storageService;
  final LLMProvider llmProvider;
  final List<RemoteModelInfo> availableModels;
  final double? dragCallBuffer;
  final void Function(double?) onDragCallBufferChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('Voice Input (STT)'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Warm-porch: header icon is chrome, not a status
                      // indicator (unlike the logReady sites below), so it
                      // gets the amber sweep rather than a theme-keep.
                      Icon(
                        Icons.mic,
                        color: AppColors.porchAmberOf(context),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Enable Voice Input',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Switch(
                    value: storageService.sttSettings.sttEnabled,
                    onChanged: (val) =>
                        storageService.sttSettings.setSttEnabled(val),
                  ),
                ],
              ),
              if (storageService.sttSettings.sttEnabled) ...[
                Divider(
                  color: AppColors.borderOf(context).withValues(alpha: 0.3),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Whisper Model',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue:
                                storageService.sttSettings.whisperModel,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceContainerOf(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'tiny.en',
                                child: Text('Tiny (~105MB, fastest)'),
                              ),
                              DropdownMenuItem(
                                value: 'base.en',
                                child: Text('Base (~155MB, balanced)'),
                              ),
                              DropdownMenuItem(
                                value: 'small.en',
                                child: Text('Small (~360MB, best accuracy)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                storageService.sttSettings.setWhisperModel(val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Download model button with progress
                Consumer<SttService>(
                  builder: (context, sttService, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The button exists only while it has a job: gone
                        // once the selected model is verified on disk
                        // (clicking it then was a no-op anyway), back if
                        // the files go missing or fail verification.
                        if (!sttService.isSelectedModelDownloaded ||
                            sttService.isDownloading)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: sttService.isDownloading
                                  ? null
                                  : () async {
                                      final ok = await sttService
                                          .downloadModel();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? '✅ Model "${storageService.sttSettings.whisperModel}" downloaded!'
                                                  : '❌ ${sttService.downloadError ?? "Download failed"}',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              icon: sttService.isDownloading
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.textSecondary(context),
                                      ),
                                    )
                                  : const Icon(Icons.download, size: 18),
                              label: Text(
                                sttService.isDownloading
                                    ? sttService.downloadStatus
                                    : 'Download Model',
                              ),
                              style: OutlinedButton.styleFrom(
                                // theme-keep: download-ready status green
                                foregroundColor: AppColors.logReady,
                                side: BorderSide(color: AppColors.logReady),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        if (sttService.isDownloading) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: sttService.downloadProgress > 0
                                  ? sttService.downloadProgress
                                  : null,
                              backgroundColor: AppColors.borderOf(
                                context,
                              ).withValues(alpha: 0.3),
                              // theme-keep: download-ready status green
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.logReady,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        // Verified on-disk state for the SELECTED size, so
                        // "did it actually download?" is never a mystery.
                        Row(
                          children: [
                            Icon(
                              sttService.isSelectedModelDownloaded
                                  ? Icons.check_circle
                                  : Icons.info_outline,
                              size: 13,
                              // theme-keep: download-ready status green
                              color: sttService.isSelectedModelDownloaded
                                  ? AppColors.logReady
                                  : AppColors.textTertiary(context),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                sttService.isSelectedModelDownloaded
                                    ? 'Model files verified on disk — '
                                          'voice input is ready.'
                                    : 'Not downloaded yet — use the button '
                                          'above, or it downloads on first '
                                          'use.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Microphone selector
                Consumer<SttService>(
                  builder: (context, sttService, _) {
                    // Auto-refresh devices on first render so dropdown is populated
                    if (sttService.inputDevices.isEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        sttService.refreshInputDevices();
                      });
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Microphone',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        sttService.inputDevices.any(
                                          (d) =>
                                              d.id ==
                                              sttService.selectedDeviceId,
                                        )
                                        ? sttService.selectedDeviceId
                                        : null,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: AppColors.surfaceContainerOf(
                                        context,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('System Default'),
                                      ),
                                      ...sttService.inputDevices.map(
                                        (d) => DropdownMenuItem<String>(
                                          value: d.id,
                                          child: Text(
                                            d.label,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) =>
                                        sttService.setSelectedDevice(val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                Icons.refresh,
                                size: 20,
                                color: AppColors.textSecondary(context),
                              ),
                              tooltip: 'Refresh devices',
                              onPressed: () => sttService.refreshInputDevices(),
                            ),
                          ],
                        ),
                        if (sttService.inputDevices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'No microphones detected. Click refresh to scan.',
                              style: TextStyle(
                                fontSize: 11,
                                // theme-keep: warning semantics
                                color: AppColors.logWarn.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                ...voiceCallSettingsChildren(
                  context,
                  storageService: storageService,
                  llmProvider: llmProvider,
                  availableModels: availableModels,
                  dragCallBuffer: dragCallBuffer,
                  onDragCallBufferChanged: onDragCallBufferChanged,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
