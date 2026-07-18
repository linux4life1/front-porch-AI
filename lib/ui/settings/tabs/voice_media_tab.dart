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
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/photo_understanding_card.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/settings/widgets/image_gen_enable_section.dart';
import 'package:front_porch_ai/ui/settings/widgets/legacy_cleanup_card.dart';

/// Voice & Media tab extracted from settings_page god file (Stage 5).
/// Pure lift of _buildVoiceMediaTab + voice-specific helpers + onnx button.
/// Shared local state (drag buffer, available models) passed via constructor
/// to keep owning state in _SettingsPageState (per plan). AppColors used
/// exclusively for all colors/surfaces/text/icons (no new hard-coded
/// Color(0xFF...) or raw Colors.whiteXX/Colors.blackXX). Follows patterns
/// from prior extractions (const, composition, no build side effects).
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

  String _expressionModeLabel(String mode) {
    switch (mode) {
      case 'llm':
        return 'LLM';
      case 'onnx':
        return 'ONNX';
      case 'manual':
        return 'Manual';
      default:
        return mode;
    }
  }

  String _expressionDisplayLabel(String mode) {
    switch (mode) {
      case 'sidebar':
        return 'Sidebar';
      case 'background':
        return 'Background';
      case 'both':
        return 'Both';
      default:
        return mode;
    }
  }

  /// Download button shown in the Expression Images settings row.
  /// Lifted verbatim (with mounted -> context.mounted, AppColors fixes).
  Widget _buildOnnxDownloadButton(
    ExpressionClassifierService service,
    BuildContext context,
  ) {
    if (service.modelReady || service.isModelCached) {
      // Model already downloaded — show a ready indicator
      return Tooltip(
        message: 'Expression model downloaded and ready',
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.logReady.withValues(alpha: 0.15),
            border: Border.all(
              color: AppColors.logReady.withValues(alpha: 0.5),
            ),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 18,
            color: AppColors.logReady,
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Download ONNX model for local expression classification',
      child: IconButton(
        icon: service.isDownloading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.logReady,
                ),
              )
            : const Icon(Icons.download_rounded, size: 20),
        onPressed: service.isDownloading
            ? null
            : () async {
                final ok = await service.triggerOnnxDownload();
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not start download. Check your internet connection.',
                      ),
                    ),
                  );
                }
              },
        style: IconButton.styleFrom(
          backgroundColor: service.isDownloading
              ? AppColors.textTertiary(context).withValues(alpha: 0.3)
              : AppColors.logReady.withValues(alpha: 0.2),
          foregroundColor: AppColors.logReady,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final llmProvider = Provider.of<LLMProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
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
                Icon(Icons.volume_up, color: AppColors.userBubble, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _engineDisplayName(storageService.ttsEngine),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        storageService.ttsEnabled
                            ? () {
                                final voiceKey = storageService.ttsVoiceModel;
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
                    backgroundColor: AppColors.userBubble,
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),

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
                        Icon(Icons.mic, color: AppColors.logReady, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          'Enable Voice Input',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Switch(
                      value: storageService.sttEnabled,
                      onChanged: (val) => storageService.setSttEnabled(val),
                    ),
                  ],
                ),
                if (storageService.sttEnabled) ...[
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
                              initialValue: storageService.whisperModel,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceContainerOf(
                                  context,
                                ),
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
                                  storageService.setWhisperModel(val);
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
                                                  ? '✅ Model "${storageService.whisperModel}" downloaded!'
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                onPressed: () =>
                                    sttService.refreshInputDevices(),
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
                                  color: AppColors.logWarn.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Voice call model selector — backend-aware
                  Builder(
                    builder: (context) {
                      final isLocal =
                          llmProvider.activeBackend == BackendType.kobold;
                      final List<Map<String, dynamic>> callModels;
                      if (isLocal) {
                        callModels = modelManager.models.map((f) {
                          final basename = f.path
                              .split('/')
                              .last
                              .split('\\')
                              .last;
                          final displayName = basename.replaceAll(
                            RegExp(r'\.gguf$', caseSensitive: false),
                            '',
                          );
                          return {'id': f.path, 'name': displayName};
                        }).toList();
                      } else {
                        callModels = availableModels
                            .map((m) => {'id': m.id, 'name': m.name})
                            .toList();
                      }

                      final recommended = callModels
                          .where((m) {
                            final lower = m['name']!.toLowerCase();
                            return lower.contains('mini') ||
                                lower.contains('tiny') ||
                                lower.contains('1b') ||
                                lower.contains('3b') ||
                                lower.contains('4b') ||
                                lower.contains('flash') ||
                                lower.contains('haiku') ||
                                lower.contains('nano') ||
                                lower.contains('small');
                          })
                          .take(8)
                          .toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Voice Call Model',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isLocal
                                      ? AppColors.logWarn.withValues(
                                          alpha: 0.15,
                                        )
                                      : AppColors.userBubble.withValues(
                                          alpha: 0.15,
                                        ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isLocal ? 'Local' : 'API',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isLocal
                                        ? AppColors.logWarn
                                        : AppColors.userBubble,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (callModels.isNotEmpty)
                            DropdownButtonFormField<String>(
                              initialValue: storageService.callModelName.isEmpty
                                  ? ''
                                  : (callModels.any(
                                          (m) =>
                                              m['id'] ==
                                              storageService.callModelName,
                                        )
                                        ? storageService.callModelName
                                        : ''),
                              isExpanded: true,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceContainerOf(
                                  context,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: [
                                DropdownMenuItem<String>(
                                  value: '',
                                  child: Text(
                                    'Same as main model',
                                    style: TextStyle(
                                      color: AppColors.textTertiary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                ...callModels.map((m) {
                                  final name = m['name']!;
                                  final isRec = recommended.any(
                                    (r) => r['id'] == m['id'],
                                  );
                                  return DropdownMenuItem<String>(
                                    value: m['id'],
                                    child: Row(
                                      children: [
                                        if (isRec) ...[
                                          Icon(
                                            Icons.star,
                                            size: 12,
                                            color: AppColors.dialogue,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            name.length > 45
                                                ? '${name.substring(0, 42)}...'
                                                : name,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  storageService.setCallModelName(val);
                                }
                              },
                            )
                          else
                            TextFormField(
                              initialValue: storageService.callModelName,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceContainerOf(
                                  context,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                hintText: isLocal
                                    ? 'No local models found — add models in Model Manager'
                                    : 'Enter model ID or configure API first',
                                hintStyle: TextStyle(
                                  color: AppColors.textTertiary(context),
                                  fontSize: 13,
                                ),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (val) =>
                                  storageService.setCallModelName(val.trim()),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            '💡 Use a smaller, faster model for voice calls.\n'
                            'Reasoning/thinking models add latency — not recommended.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                          if (recommended.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '⭐ Recommended for voice calls:',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: recommended.map((m) {
                                final name = m['name']!;
                                final id = m['id']!;
                                final isSelected =
                                    storageService.callModelName == id;
                                return ActionChip(
                                  label: Text(
                                    name.length > 30
                                        ? '${name.substring(0, 27)}...'
                                        : name,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected
                                          ? AppColors.logReady
                                          : AppColors.textSecondary(context),
                                    ),
                                  ),
                                  backgroundColor: isSelected
                                      ? AppColors.logReady.withValues(
                                          alpha: 0.15,
                                        )
                                      : AppColors.textTertiary(
                                          context,
                                        ).withValues(alpha: 0.05),
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppColors.logReady.withValues(
                                            alpha: 0.4,
                                          )
                                        : AppColors.borderOf(
                                            context,
                                          ).withValues(alpha: 0.3),
                                  ),
                                  onPressed: () =>
                                      storageService.setCallModelName(id),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Voice buffer size slider
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Voice Buffer',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          Text(
                            '${(dragCallBuffer ?? storageService.callBufferSentences.toDouble()).round()} sentences',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value:
                            dragCallBuffer ??
                            storageService.callBufferSentences.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        activeColor: AppColors.userBubble,
                        onChanged: (val) => onDragCallBufferChanged(val),
                        onChangeEnd: (val) {
                          onDragCallBufferChanged(null);
                          storageService.setCallBufferSentences(val.round());
                        },
                      ),
                      Text(
                        'Sentences to pre-generate before playback starts. '
                        'Auto-expands if generation is slow.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Call system prompt
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Call System Prompt',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              storageService.setCallSystemPrompt(
                                'You are on a live voice call. Respond naturally as if speaking on the phone. '
                                'ALWAYS write in first person \u2014 never narrate in third person. '
                                'Keep responses concise: 1-3 sentences max. '
                                'No actions, no narration, no stage directions \u2014 just speak directly.',
                              );
                            },
                            icon: const Icon(Icons.restore, size: 14),
                            label: const Text(
                              'Reset',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textTertiary(context),
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 24),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: ValueKey(storageService.callSystemPrompt.hashCode),
                        initialValue: storageService.callSystemPrompt,
                        maxLines: 4,
                        minLines: 2,
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
                          hintText:
                              'Instructions appended during voice calls...',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 13,
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                        onChanged: (val) =>
                            storageService.setCallSystemPrompt(val),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Appended to the system prompt during voice calls to control response style.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.send,
                            color: AppColors.userBubble,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Auto-send transcription',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      Switch(
                        value: storageService.autoSendTranscription,
                        onChanged: (val) =>
                            storageService.setAutoSendTranscription(val),
                      ),
                    ],
                  ),
                  Text(
                    'When enabled, transcribed text is sent automatically instead of being placed in the input field.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Self-hiding: renders nothing (header included) until the offline
          // vision helper is installed — the feature is offered only in chat.
          const PhotoUnderstandingCard(),

          const SizedBox(height: 24),
          const SectionHeader('Expression Images'),
          const SizedBox(height: 8),
          Consumer<StorageService>(
            builder: (context, storage, _) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          storage.expressionEnabled
                              ? Icons.mood
                              : Icons.mood_outlined,
                          color: storage.expressionEnabled
                              ? AppColors.presetColors[4] // purple from preset
                              : AppColors.textTertiary(context),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Expression Images',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                storage.expressionEnabled
                                    ? 'Enabled — ${_expressionModeLabel(storage.expressionClassificationMode)}, ${_expressionDisplayLabel(storage.expressionDisplayMode)}'
                                    : 'Disabled',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: storage.expressionEnabled,
                          onChanged: (val) => storage.setExpressionEnabled(val),
                          activeTrackColor: AppColors.presetColors[4],
                        ),
                      ],
                    ),
                    if (storage.expressionEnabled) ...[
                      Divider(
                        color: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 8),
                      // Classification mode dropdown and download button
                      Row(
                        children: [
                          Icon(
                            Icons.psychology,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Classification:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<String>(
                              value: storage.expressionClassificationMode,
                              isDense: true,
                              underline: const SizedBox(),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary(context),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'llm',
                                  child: Text('LLM (Realism Engine)'),
                                ),
                                DropdownMenuItem(
                                  value: 'onnx',
                                  child: Text('Local ONNX Model'),
                                ),
                                DropdownMenuItem(
                                  value: 'manual',
                                  child: Text('Manual Only'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  storage.setExpressionClassificationMode(val);
                                }
                              },
                            ),
                          ),
                          // Download / ready indicator for the ONNX model
                          Consumer<ExpressionClassifierService>(
                            builder: (context, expressionService, _) =>
                                _buildOnnxDownloadButton(
                                  expressionService,
                                  context,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Display mode dropdown
                      Row(
                        children: [
                          Icon(
                            Icons.view_sidebar,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Display:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<String>(
                              value: storage.expressionDisplayMode,
                              isDense: true,
                              underline: const SizedBox(),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary(context),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'sidebar',
                                  child: Text('Sidebar Only'),
                                ),
                                DropdownMenuItem(
                                  value: 'background',
                                  child: Text('Background Only'),
                                ),
                                DropdownMenuItem(
                                  value: 'both',
                                  child: Text('Both'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  storage.setExpressionDisplayMode(val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Reroll toggle
                      Row(
                        children: [
                          Icon(
                            Icons.casino,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Re-roll if same sprite repeats',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ),
                          Switch(
                            value: storage.expressionRerollSame,
                            onChanged: (val) =>
                                storage.setExpressionRerollSame(val),
                            activeTrackColor: AppColors.presetColors[4],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Emoji burst toggle
                      Row(
                        children: [
                          Icon(
                            Icons.celebration,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Expression Emoji Burst',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ),
                          Switch(
                            value: storage.expressionEmojiBurst,
                            onChanged: (val) =>
                                storage.setExpressionEmojiBurst(val),
                            activeTrackColor: AppColors.presetColors[4],
                          ),
                        ],
                      ),
                      // Burst particle size (only relevant when the burst is on)
                      if (storage.expressionEmojiBurst) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Burst emoji size',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            Text(
                              '${storage.expressionEmojiBurstSize.round()} px',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: storage.expressionEmojiBurstSize,
                          min: 12,
                          max: 60,
                          divisions: 12,
                          activeColor: AppColors.presetColors[4],
                          onChanged: (val) =>
                              storage.setExpressionEmojiBurstSize(val),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Fallback dropdown
                      Row(
                        children: [
                          Icon(
                            Icons.backup,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Fallback:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<String>(
                              value: storage.expressionFallback,
                              isDense: true,
                              underline: const SizedBox(),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary(context),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'neutral',
                                  child: Text('Neutral Sprite'),
                                ),
                                DropdownMenuItem(
                                  value: 'prime',
                                  child: Text('Prime Avatar'),
                                ),
                                DropdownMenuItem(
                                  value: 'none',
                                  child: Text('Hide'),
                                ),
                                DropdownMenuItem(
                                  value: 'emoji',
                                  child: Text('Emoji Icon'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  storage.setExpressionFallback(val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          const ImageGenEnableSection(),
          // Appears only while old-engine model files still sit on disk.
          const LegacyCleanupCard(),
        ],
      ),
    );
  }
}
