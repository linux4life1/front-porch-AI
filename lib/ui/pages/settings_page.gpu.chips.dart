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

/// Acceleration expander, GPU backend chips and the KV cache row of
/// Advanced Launch Options.
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
      // Detection reports Metal on every Mac and nowhere else.
      onMac: hw?.hasMetal,
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
        // Its own Material: the Launch Options card paints a background.
        Material(
          type: MaterialType.transparency,
          child: Theme(
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
        ),
      ],
    );
  }

  /// The cache type auto mode launches with. A preset names its own.
  Widget _buildKvCacheRow(BuildContext context, StorageService storage) {
    return Row(
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
          child: KvQuantPicker(
            value: storage.backendSettings.kvQuant,
            onChanged: (val) {
              storage.backendSettings.setKvQuant(val);
              rebuildState(() {});
            },
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message:
              'Quantizes the context window to save significant VRAM with minimal quality loss. Note: KoboldCPP dynamically disables Context Shifting when this is active.',
          child: Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.porchAmberOf(context).withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildGpuBackendChips(
    BuildContext context,
    HardwareService hardwareService,
  ) {
    // Saves all four switches, not only the one touched: all four off is "CPU
    // only", while any left unset lets the launch pick a GPU on its own.
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

    final hw = hardwareService.hardwareInfo;

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
            selectBackend(vulkan: val);
          },
        ),
        Tooltip(
          message: hw?.hasRocm == true
              ? 'Use ROCm on this AMD card (its engine downloads when picked)'
              : 'Needs an AMD card whose Linux driver offers ROCm',
          child: FilterChip(
            label: const Text('Use ROCm (AMD)'),
            selected: _useRocm,
            onSelected: hw?.hasRocm == true
                ? (val) {
                    // The driver offers it but this account may not use it:
                    // say how, rather than pick something that cannot run.
                    if (val && !hw!.rocmAccess) {
                      showRocmHelpDialog(context, driverReady: true);
                      return;
                    }
                    rebuildState(() {
                      _useRocm = val;
                      if (val) {
                        _useVulkan = false;
                        _useCublas = false;
                        _useMetal = false;
                      }
                    });
                    selectBackend(rocm: val);
                  }
                : null, // Disabled when the driver offers no ROCm
            avatar: hw?.hasRocm == true
                ? null
                : const Icon(Icons.block, size: 16),
          ),
        ),
        // Only where something can be done: an AMD card on Linux whose
        // driver offers no ROCm, or one this account may not use yet.
        if (hw != null &&
            hw.vendor == 'AMD' &&
            Platform.isLinux &&
            (!hw.hasRocm || !hw.rocmAccess))
          TextButton(
            onPressed: () =>
                showRocmHelpDialog(context, driverReady: hw.hasRocm),
            child: const Text('Why can\'t I use ROCm?'),
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
                    selectBackend(cublas: val);
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
                    selectBackend(metal: val);
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
