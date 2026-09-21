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

part of 'model_settings_dialog.dart';

/// The local (KoboldCpp) backend's settings panel: model dropdown, vision
/// projector field, preset picker, hardware info, GPU/context fields, KV
/// quantization, and the Auto-Configure / Start-Restart buttons. Split out of
/// `model_settings_dialog.dart` — verbatim except `setState` -> `rebuildState`
/// (extensions can't call a State's protected members) and the amber ->
/// formMasterAccent retheme noted inline below.
extension _ModelSettingsLocalSection on _ModelSettingsDialogState {
  Widget _buildLocalSettings() {
    final storage = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final hardwareService = Provider.of<HardwareService>(context);
    final koboldService = Provider.of<KoboldService>(context);

    // Auto-select first model if none selected and models exist.
    // Skip when a kcpps preset with a valid model is active (use "Managed by kcpps").
    // Gate the exists memo on kcppsHasModel — same short-circuit the old
    // `kcppsHasModel && kcppsModelFileExists` used — so a rebuild without a
    // preset never reads kcppsModelPath or stats a file.
    final kcppsModelExists =
        storage.backendSettings.kcppsHasModel &&
        _kcppsModelExists.of(storage.backendSettings.kcppsModelPath);
    if (_selectedModelPath == null &&
        modelManager.models.isNotEmpty &&
        !kcppsModelExists) {
      _selectedModelPath = modelManager.models.first.path;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LowPerfCpuWarning(margin: EdgeInsets.only(bottom: 12)),
        ModelSelector(
          models: modelManager.models,
          selectedModelPath: _selectedModelPath,
          showManagedByKcpps:
              storage.backendSettings.kcppsHasModel && kcppsModelExists,
          onChanged: (val) {
            if (val == null) {
              rebuildState(() {
                _selectedModelPath = null;
              });
            } else {
              rebuildState(() {
                _selectedModelPath = val;
              });
              storage.backendSettings.setLastUsedModelPath(val);
              final savedPreset = storage.presetSettings.modelPresetMap[val];
              if (savedPreset != null &&
                  savedPreset.isNotEmpty &&
                  _presetFileExists.of(savedPreset)) {
                storage.backendSettings.setActiveKcppsPath(savedPreset);
              } else {
                storage.backendSettings.setActiveKcppsPath(null);
              }
              _applyAutoConfiguration();
            }
          },
        ),

        // Vision projector (mmproj) — only meaningful for a concrete local GGUF;
        // the field self-hides when no model file is selected (a preset owns it)
        // and greys out for text-only / vision-built-in models.
        VisionProjectorField(
          modelPath: _selectedModelPath,
          storage: storage,
          onChanged: () => rebuildState(() {}),
        ),

        const SizedBox(height: 16),

        // Preset selection
        Consumer<StorageService>(
          builder: (context, storage, _) {
            final isPresetActive =
                storage.backendSettings.activeKcppsPath != null &&
                storage.backendSettings.activeKcppsPath!.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuration Preset',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 8),
                KcppsSelector(
                  storage: storage,
                  localPresets: _localPresets,
                  hint: 'None (Use App Settings)',
                  onChanged: (val) {
                    storage.backendSettings.setActiveKcppsPath(val);
                    if (_selectedModelPath != null && val != null) {
                      storage.presetSettings.setModelPreset(
                        _selectedModelPath!,
                        val,
                      );
                    } else if (_selectedModelPath != null && val == null) {
                      storage.presetSettings.setModelPreset(
                        _selectedModelPath!,
                        '',
                      );
                    }
                    if (val != null &&
                        storage.backendSettings.kcppsHasModel &&
                        _kcppsModelExists.of(
                          storage.backendSettings.kcppsModelPath,
                        )) {
                      rebuildState(() {
                        _selectedModelPath = null;
                      });
                    }
                  },
                  onExternalClear: () {
                    storage.backendSettings.setActiveKcppsPath(null);
                    if (_selectedModelPath != null) {
                      storage.presetSettings.setModelPreset(
                        _selectedModelPath!,
                        '',
                      );
                    }
                  },
                  onBrowsePicked: (path) {
                    if (_selectedModelPath != null) {
                      storage.presetSettings.setModelPreset(
                        _selectedModelPath!,
                        path,
                      );
                    }
                    _scanLocalPresets();
                    if (storage.backendSettings.kcppsHasModel &&
                        _kcppsModelExists.of(
                          storage.backendSettings.kcppsModelPath,
                        )) {
                      rebuildState(() {
                        _selectedModelPath = null;
                      });
                    }
                  },
                  onModelStatusChanged: (_) {
                    rebuildState(() {});
                  },
                ),
                const SizedBox(height: 16),

                // When a preset is active, show a clear label instead of just fading
                // the fields. Users need to know these controls are overridden.
                if (isPresetActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      // Retheme: was Colors.amber, matching the oMLX banner's
                      // formMasterAccent 0.12/0.3 fill+border pattern below.
                      color: AppColors.formMasterAccent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppColors.formMasterAccent.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.formMasterAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Controlled by preset: ${path_lib.basename(storage.backendSettings.activeKcppsPath!)}',
                            style: const TextStyle(
                              color: AppColors.formMasterAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                IgnorePointer(
                  ignoring: isPresetActive,
                  child: Opacity(
                    opacity: isPresetActive ? 0.4 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hardware Info
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: hardwareService.isDetecting
                              ? const Center(child: CircularProgressIndicator())
                              : hardwareService.hardwareInfo == null
                              ? const Text(
                                  'Hardware not detected.',
                                  // theme-keep: detection-error text
                                  style: TextStyle(color: Colors.redAccent),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow(
                                      'GPU',
                                      hardwareService.hardwareInfo!.gpuName,
                                    ),
                                    _buildInfoRow(
                                      'VRAM',
                                      '${hardwareService.hardwareInfo!.vramMb} MB${hardwareService.hardwareInfo!.isSharedMemory ? ' (Shared)' : ''}',
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: 'GPU Layers',
                                controller: _gpuLayersController,
                                isNumber: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: IgnorePointer(
                                ignoring: _isPresetActive(context),
                                child: Opacity(
                                  opacity: _isPresetActive(context) ? 0.5 : 1.0,
                                  child: _isPresetActive(context)
                                      ? Tooltip(
                                          message:
                                              'Context size is controlled by the active .kcpps preset and cannot be edited here.',
                                          child: _buildTextField(
                                            label: 'Context Size',
                                            controller: _contextSizeController,
                                            isNumber: true,
                                          ),
                                        )
                                      : _buildTextField(
                                          label: 'Context Size',
                                          controller: _contextSizeController,
                                          isNumber: true,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'KV Quantization:',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: Provider.of<StorageService>(
                                    context,
                                  ).backendSettings.kvQuantizationLevel,
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
                                      Provider.of<StorageService>(
                                        context,
                                        listen: false,
                                      ).backendSettings.setKvQuantizationLevel(
                                        val,
                                      );
                                      rebuildState(() {});
                                    }
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: 0,
                                      child: Text('0 - None (FP16)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text('1 - 8-Bit Q8'),
                                    ),
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text('2 - 4-Bit Q4'),
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
                                color: AppColors.iconSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                IgnorePointer(
                  ignoring: isPresetActive,
                  child: Opacity(
                    opacity: isPresetActive ? 0.4 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: _applyAutoConfiguration,
                              icon: const Icon(
                                Icons.auto_fix_high,
                                // Retheme: was Colors.amber.
                                color: AppColors.formMasterAccent,
                              ),
                              label: const Text(
                                'Auto-Configure',
                                style: TextStyle(
                                  color: AppColors.formMasterAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _restartBackend,
            icon: const Icon(Icons.refresh),
            label: Text(
              _isPresetActive(context)
                  ? (koboldService.isRunning
                        ? 'Restart with Preset'
                        : 'Start with Preset')
                  : (koboldService.isRunning
                        ? 'Restart Backend'
                        : 'Start Backend'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
