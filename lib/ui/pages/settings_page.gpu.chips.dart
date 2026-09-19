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

/// Context slider, acceleration expander, and GPU backend chips.
extension _SettingsGpuChips on _SettingsPageState {
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
                  storage.backendSettings.setUseVulkan(null);
                  storage.backendSettings.setUseRocm(null);
                  storage.backendSettings.setUseCublas(null);
                  storage.backendSettings.setUseMetal(null);
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
              storageService.backendSettings.setContextSize(newSize);
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
                storageService.backendSettings.setContextSize(size);
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
      ss.backendSettings.setUseVulkan(vulkan);
      ss.backendSettings.setUseRocm(rocm);
      ss.backendSettings.setUseCublas(cublas);
      ss.backendSettings.setUseMetal(metal);
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
              ).backendSettings.setUseVulkan(false);
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
                      ).backendSettings.setUseRocm(false);
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
                      ).backendSettings.setUseCublas(false);
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
                      ).backendSettings.setUseMetal(false);
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
