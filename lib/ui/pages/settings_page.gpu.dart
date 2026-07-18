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
                                    storageService.setContextSize(parsed);
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
                                  value: storageService.kvQuantizationLevel,
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
                                      storageService.setKvQuantizationLevel(
                                        val,
                                      );
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

  /// Acceleration "just works": a status line showing what automatic mode
  /// resolved to, with the manual backend chips (Vulkan/ROCm/CUDA/Metal —
  /// confusing to most users) tucked into a collapsed Advanced expander.
  Widget _buildAccelerationSection(
    BuildContext context,
    HardwareService hardwareService,
  ) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final bs = storage.backendSettings;
    final hw = hardwareService.hardwareInfo;
    final auto = GpuBackendResolver.isAutomatic(
      userCublas: bs.useCublas,
      userVulkan: bs.useVulkan,
      userRocm: bs.useRocm,
      userMetal: bs.useMetal,
    );
    final backend = GpuBackendResolver.resolve(
      userCublas: bs.useCublas,
      userVulkan: bs.useVulkan,
      userRocm: bs.useRocm,
      userMetal: bs.useMetal,
      hasCuda: hw?.hasCuda ?? false,
      vendor: hw?.vendor ?? 'Unknown',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              auto ? Icons.auto_awesome : Icons.tune,
              size: 16,
              color: AppColors.porchAmberOf(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                auto
                    ? 'Acceleration: Automatic — '
                          '${GpuBackendResolver.describe(backend, hw?.vendor ?? 'Unknown')}'
                    : 'Acceleration: Manual — '
                          '${GpuBackendResolver.describe(backend, hw?.vendor ?? 'Unknown')}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
            if (!auto)
              TextButton(
                onPressed: () {
                  storage.setUseVulkan(null);
                  storage.setUseRocm(null);
                  storage.setUseCublas(null);
                  storage.setUseMetal(null);
                  rebuildState(() {
                    _useVulkan = false;
                    _useRocm = false;
                    _useCublas = false;
                    _useMetal = false;
                  });
                },
                child: const Text('Reset to Automatic'),
              ),
          ],
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Advanced: manual backend override',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary(context),
              ),
            ),
            children: [_buildGpuBackendChips(context, hardwareService)],
          ),
        ),
      ],
    );
  }

  Widget _buildContextSlider(
    BuildContext context,
    StorageService storageService,
    Color accent,
  ) {
    final currentVal = int.tryParse(_contextSizeController.text) ?? 16384;
    // Map context size to slider position.
    final presets = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072];
    int closestIdx = 0;
    int closestDist = (presets[0] - currentVal).abs();
    for (int i = 1; i < presets.length; i++) {
      final dist = (presets[i] - currentVal).abs();
      if (dist < closestDist) {
        closestDist = dist;
        closestIdx = i;
      }
    }

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: accent.withValues(alpha: 0.15),
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: _dragContextSize ?? closestIdx.toDouble(),
            min: 0,
            max: (presets.length - 1).toDouble(),
            divisions: presets.length - 1,
            onChanged: (val) {
              rebuildState(() => _dragContextSize = val);
              _contextSizeController.text = presets[val.round()].toString();
            },
            onChangeEnd: (val) {
              _dragContextSize = null;
              final newSize = presets[val.round()];
              _contextSizeController.text = newSize.toString();
              storageService.setContextSize(newSize);
              rebuildState(() {});
            },
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [512, 2048, 4096, 8192, 16384, 32768, 65536, 131072].map((
            size,
          ) {
            final isSelected = currentVal == size;
            final label = size >= 1024 ? '${size ~/ 1024}K' : '$size';
            return ChoiceChip(
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? AppColors.onChaosAccent
                      : AppColors.textTertiary(context),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: accent,
              backgroundColor: AppColors.textPrimary(
                context,
              ).withValues(alpha: 0.05),
              side: BorderSide(
                color: isSelected ? accent : AppColors.borderOf(context),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) {
                _contextSizeController.text = size.toString();
                storageService.setContextSize(size);
                rebuildState(() {});
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGpuBackendChips(
    BuildContext context,
    HardwareService hardwareService,
  ) {
    void selectBackend({
      bool vulkan = false,
      bool rocm = false,
      bool cublas = false,
      bool metal = false,
    }) {
      final ss = Provider.of<StorageService>(context, listen: false);
      ss.setUseVulkan(vulkan);
      ss.setUseRocm(rocm);
      ss.setUseCublas(cublas);
      ss.setUseMetal(metal);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: const Text('Use Vulkan'),
          selected: _useVulkan,
          onSelected: (val) {
            rebuildState(() {
              _useVulkan = val;
              if (val) {
                _useCublas = false;
                _useRocm = false;
                _useMetal = false;
              }
            });
            if (val) {
              selectBackend(vulkan: true);
            } else {
              Provider.of<StorageService>(
                context,
                listen: false,
              ).setUseVulkan(false);
            }
          },
        ),
        Tooltip(
          message: hardwareService.hardwareInfo?.hasRocm == true
              ? 'Use ROCm for native AMD GPU acceleration'
              : 'Requires ROCm installation (AMD GPU)',
          child: FilterChip(
            label: const Text('Use ROCm (AMD)'),
            selected: _useRocm,
            onSelected: hardwareService.hardwareInfo?.hasRocm == true
                ? (val) {
                    rebuildState(() {
                      _useRocm = val;
                      if (val) {
                        _useVulkan = false;
                        _useCublas = false;
                        _useMetal = false;
                      }
                    });
                    if (val) {
                      selectBackend(rocm: true);
                    } else {
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).setUseRocm(false);
                    }
                  }
                : null, // Disabled if ROCm not installed
            avatar: hardwareService.hardwareInfo?.hasRocm == true
                ? null
                : const Icon(Icons.block, size: 16),
          ),
        ),
        Tooltip(
          message: hardwareService.hardwareInfo?.vendor == 'Nvidia'
              ? 'Use CUDA (NVIDIA only)'
              : 'Requires NVIDIA GPU',
          child: FilterChip(
            label: const Text('Use CuBLAS (Nvidia)'),
            selected: _useCublas,
            onSelected: hardwareService.hardwareInfo?.vendor == 'Nvidia'
                ? (val) {
                    rebuildState(() {
                      _useCublas = val;
                      if (val) {
                        _useVulkan = false;
                        _useRocm = false;
                        _useMetal = false;
                      }
                    });
                    if (val) {
                      selectBackend(cublas: true);
                    } else {
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).setUseCublas(false);
                    }
                  }
                : null, // Disabled if not Nvidia
            avatar: hardwareService.hardwareInfo?.vendor == 'Nvidia'
                ? null
                : const Icon(Icons.block, size: 16),
          ),
        ),
        Tooltip(
          message: hardwareService.hardwareInfo?.hasMetal == true
              ? 'Use Metal (Apple Silicon/Mac)'
              : 'Requires MacOS with Metal support',
          child: FilterChip(
            label: const Text('Use Metal (MacOS)'),
            selected: _useMetal,
            onSelected: hardwareService.hardwareInfo?.hasMetal == true
                ? (val) {
                    rebuildState(() {
                      _useMetal = val;
                      if (val) {
                        _useVulkan = false;
                        _useCublas = false;
                        _useRocm = false;
                      }
                    });
                    if (val) {
                      selectBackend(metal: true);
                    } else {
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).setUseMetal(false);
                    }
                  }
                : null, // Disabled if not MacOS/Metal
            avatar: hardwareService.hardwareInfo?.hasMetal == true
                ? null
                : const Icon(Icons.block, size: 16),
          ),
        ),
      ],
    );
  }
}
