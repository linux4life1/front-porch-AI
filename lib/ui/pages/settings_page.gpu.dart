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

/// GPU/context controls of the Advanced tab: context-window slider + presets,
/// KV-cache quantization, GPU layers, and the GPU backend selector chips.
/// Extracted from the inline _buildAdvancedTab; direct state access preserves
/// behavior. Warm-porch: primary interactive accents use amber.
extension _SettingsGpuControls on _SettingsPageState {
  Widget _buildGpuControls(
    BuildContext context,
    StorageService storageService,
    HardwareService hardwareService,
    bool isPresetActive,
  ) {
    final theme = Theme.of(context);
    final accent = AppColors.porchAmberOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isPresetActive) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A configuration preset is active. Advanced settings are '
                    'managed by the preset and cannot be edited here.',
                    style: theme.textTheme.bodySmall?.copyWith(color: accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        IgnorePointer(
          ignoring: isPresetActive,
          child: Opacity(
            opacity: isPresetActive ? 0.4 : 1.0,
            child: Tooltip(
              message: isPresetActive
                  ? 'Context size is controlled by the active .kcpps preset and cannot be edited here.'
                  : '',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.straighten, color: accent, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              'Context Window',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _contextSizeController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.scaffoldBackgroundColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: accent.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  final parsed = int.tryParse(val);
                                  if (parsed != null && parsed > 0) {
                                    storageService.backendSettings
                                        .setContextSize(parsed);
                                    rebuildState(() {}); // refresh VRAM gauge
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildContextSlider(context, storageService, accent),
                        const SizedBox(height: 12),
                        Divider(color: AppColors.borderOf(context)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'KV Cache Quantization:',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: storageService
                                      .backendSettings
                                      .kvQuantizationLevel,
                                  isExpanded: true,
                                  dropdownColor: AppColors.surfaceContainerOf(
                                    context,
                                  ),
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 13,
                                  ),
                                  onChanged: (val) {
                                    if (val != null) {
                                      storageService.backendSettings
                                          .setKvQuantizationLevel(val);
                                      rebuildState(() {}); // Refresh VRAM gauge
                                    }
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: 0,
                                      child: Text(
                                        '0 - None (Highest Quality, FP16)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text(
                                        '1 - 8-Bit Q8 (~50% VRAM Savings)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text(
                                        '2 - 4-Bit Q4 (~75% VRAM Savings)',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message:
                                  'Quantizes the context window to save significant VRAM with minimal quality loss. Note: KoboldCPP dynamically disables Context Shifting when this is active.',
                              child: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: accent.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Larger context = more memory per conversation. Auto-configure adjusts GPU layers to fit.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // GPU Layers.
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'GPU Layers',
                controller: _gpuLayersController,
                context: context,
                isNumber: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildAccelerationSection(context, hardwareService),
      ],
    );
  }
}
