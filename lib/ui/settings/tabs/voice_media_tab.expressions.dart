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

/// Expression Images section of the Voice & Media tab: enable switch,
/// classification-mode dropdown (+ ONNX download button), display-mode
/// dropdown, reroll switch, emoji-burst switch + size slider, and fallback
/// dropdown. Lifted verbatim from the pre-split god file. Fully
/// self-contained: reads storage/expression state via its own Consumers, so
/// it needs only [BuildContext] from the shell.
extension _VoiceMediaExpressionSection on VoiceMediaTab {
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
      // theme-keep: download-ready status green (this whole ready/downloading
      // cluster, through the IconButton.styleFrom below)
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
                        'Download failed. Check your internet connection and try again.',
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

  Widget _buildExpressionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                        // Warm-porch: was AppColors.presetColors[4] (purple)
                        // — nothing semantic requires purple here, so it
                        // joins the amber sweep like the toggles/slider below.
                        color: storage.expressionEnabled
                            ? AppColors.porchAmberOf(context)
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
                        activeTrackColor: AppColors.porchAmberOf(context),
                      ),
                    ],
                  ),
                  if (storage.expressionEnabled) ...[
                    Divider(
                      color: AppColors.borderOf(context).withValues(alpha: 0.3),
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
                          activeTrackColor: AppColors.porchAmberOf(context),
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
                          activeTrackColor: AppColors.porchAmberOf(context),
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
                        activeColor: AppColors.porchAmberOf(context),
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
      ],
    );
  }
}
