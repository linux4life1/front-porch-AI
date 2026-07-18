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

part of 'settings_page.dart';

/// Hardware & GPU block of the Advanced tab: the VRAM gauge card plus the
/// Auto-Configure action. The GPU/context controls (context window, GPU
/// layers, backend chips) live in settings_page.gpu.dart. Extracted from the
/// inline _buildAdvancedTab; direct state access preserves behavior.
/// Warm-porch: model=amber, context=honey, status green/amber/red.
extension _SettingsHardware on _SettingsPageState {
  Widget _buildHardwareGpuSection(
    BuildContext context,
    StorageService storageService,
    HardwareService hardwareService,
    LLMProvider llmProvider,
    bool isPresetActive,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader('Hardware & GPU'),
            TextButton.icon(
              onPressed: _autoConfigure,
              icon: Icon(
                Icons.auto_fix_high,
                color: AppColors.porchAmberOf(context),
              ),
              label: Text(
                'Auto-Configure',
                style: TextStyle(color: AppColors.porchAmberOf(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Hardware Info with VRAM Gauge (always shown).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: hardwareService.isDetecting
              ? const Center(child: CircularProgressIndicator())
              : hardwareService.hardwareInfo == null
              ? Text(
                  'Hardware not detected.',
                  style: TextStyle(color: AppColors.negativeAccentOf(context)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.memory,
                          color: AppColors.porchAmberOf(context),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hardwareService.hardwareInfo!.gpuName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (llmProvider.isLocal)
                      _buildVramGauge(context, storageService, hardwareService)
                    else ...[
                      // Remote API — show total VRAM only, no usage estimate.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          height: 20,
                          width: double.infinity,
                          color: AppColors.textPrimary(
                            context,
                          ).withValues(alpha: 0.08),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildVramLegendDot(
                            AppColors.textTertiary(context),
                            'Total ${hardwareService.hardwareInfo!.vramMb} MB',
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Remote API — GPU not in use',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _buildGpuControls(
          context,
          storageService,
          hardwareService,
          isPresetActive,
        ),
      ],
    );
  }

  /// The local-backend VRAM usage gauge (model + context estimate vs total).
  Widget _buildVramGauge(
    BuildContext context,
    StorageService storageService,
    HardwareService hardwareService,
  ) {
    return FutureBuilder<int?>(
      future: _selectedModelPath != null
          ? Provider.of<ModelManager>(
              context,
              listen: false,
            ).getKvCacheBytesPerToken(_selectedModelPath!)
          : Future.value(null),
      builder: (context, snapshot) {
        final totalVram = hardwareService.hardwareInfo!.vramMb.toDouble();
        if (totalVram <= 0) return const SizedBox.shrink();

        // Estimate model VRAM usage from model size.
        final modelSizeMb = _getSelectedModelSizeMb();
        final contextSize = int.tryParse(_contextSizeController.text) ?? 4096;

        // Use exact KV cost if parsed, else fallback to 100MB per 1k heuristic.
        final kvBytesPerToken = snapshot.data;
        double contextVramMb = kvBytesPerToken != null
            ? (contextSize * kvBytesPerToken / (1024 * 1024))
            : (contextSize / 1024 * 100.0);

        if (storageService.kvQuantizationLevel == 1) {
          contextVramMb *= 0.5;
        } else if (storageService.kvQuantizationLevel == 2) {
          contextVramMb *= 0.25;
        }

        final gpuLayers = int.tryParse(_gpuLayersController.text) ?? 0;

        // Improved model VRAM estimate using real architecture data when available.
        double modelVramMb;
        if (gpuLayers >= 99) {
          modelVramMb = modelSizeMb.toDouble();
        } else {
          final archInfo = _selectedModelPath != null
              ? Provider.of<ModelManager>(
                  context,
                  listen: false,
                ).getCachedModelArchitectureInfo(_selectedModelPath!)
              : null;
          if (archInfo != null && archInfo.nLayers > 0) {
            final bytesPerLayer = archInfo.estimateBytesPerLayer(
              (modelSizeMb * 1024 * 1024).toInt(),
            );
            modelVramMb = (bytesPerLayer * gpuLayers / (1024 * 1024))
                .toDouble();
          } else {
            // Fallback to old heuristic only when we have no architecture data.
            modelVramMb = (modelSizeMb * (gpuLayers / 40.0)).clamp(
              0,
              modelSizeMb.toDouble(),
            );
          }
        }
        final usedVram = modelVramMb + contextVramMb;
        final usedRatio = (usedVram / totalVram).clamp(0.0, 1.0);
        final modelRatio = (modelVramMb / totalVram).clamp(0.0, 1.0);
        final contextRatio = (contextVramMb / totalVram).clamp(0.0, usedRatio);
        final freeVram = (totalVram - usedVram).clamp(0, totalVram);

        Color gaugeColor;
        if (usedRatio > 0.95) {
          gaugeColor = AppColors.negativeAccentOf(context);
        } else if (usedRatio > 0.8) {
          gaugeColor = AppColors.taskAccentOf(context);
        } else {
          gaugeColor = AppColors.bondHighOf(context);
        }

        final modelColor = AppColors.porchAmberOf(context);
        final contextColor = AppColors.porchHoneyOf(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final modelWidth = totalWidth * modelRatio;
                final contextWidth = totalWidth * contextRatio;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 20,
                    child: Stack(
                      children: [
                        // Background (free).
                        Container(
                          width: double.infinity,
                          color: AppColors.textPrimary(
                            context,
                          ).withValues(alpha: 0.08),
                        ),
                        // Model portion (starts at left).
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: modelWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  modelColor,
                                  modelColor.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Context portion (starts exactly where model ends).
                        if (contextWidth > 0)
                          Positioned(
                            left: modelWidth,
                            top: 0,
                            bottom: 0,
                            width: contextWidth,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    contextColor,
                                    contextColor.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildVramLegendDot(
                  modelColor,
                  'Model ~${modelVramMb.round()} MB',
                ),
                const SizedBox(width: 16),
                _buildVramLegendDot(
                  contextColor,
                  'Context ~${contextVramMb.round()} MB',
                ),
                const SizedBox(width: 16),
                _buildVramLegendDot(
                  AppColors.textTertiary(context),
                  'Free ~${freeVram.round()} MB',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${usedVram.round()} / ${totalVram.round()} MB used',
              style: TextStyle(
                fontSize: 11,
                color: gaugeColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Small colored dot + label for the VRAM gauge legend.
  Widget _buildVramLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  /// Estimate the selected model's file size in MB for the VRAM gauge.
  int _getSelectedModelSizeMb() {
    if (_selectedModelPath == null) return 0;
    try {
      final file = File(_selectedModelPath!);
      if (file.existsSync()) {
        return (file.lengthSync() / (1024 * 1024)).round();
      }
    } catch (_) {}
    return 0;
  }
}
