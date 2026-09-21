// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'setup_step.dart';

/// Extra Settings body and field helpers for [SetupStep].
extension SetupStepFields on SetupStep {
  Widget _inputLabel(
    BuildContext context,
    String text, {
    bool required = false,
  }) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(
              color: AppColors.resolve(
                context,
                Colors.redAccent,
                Colors.red.shade700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExtraSettingsBody(BuildContext context, CreatorState state) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final hardwareService = Provider.of<HardwareService>(
      context,
      listen: false,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KcppsSelector(
            storage: storage,
            localPresets: state.localPresets,
            hint: 'Optional \u2014 select a .kcpps preset',
            onChanged: (val) {
              storage.backendSettings.setActiveKcppsPath(val);
              if (val != null &&
                  storage.backendSettings.kcppsHasModel &&
                  storage.backendSettings.kcppsModelFileExists) {
                state.selectedLocalModelPath = '';
                state.notify();
              }
            },
            onExternalClear: () =>
                storage.backendSettings.setActiveKcppsPath(null),
            onBrowsePicked: (_) {
              if (storage.backendSettings.kcppsHasModel &&
                  storage.backendSettings.kcppsModelFileExists) {
                state.selectedLocalModelPath = '';
                state.notify();
              }
            },
            onModelStatusChanged: (_) => state.notify(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: hardwareService.isDetecting
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hardwareService.hardwareInfo == null
                ? const Text(
                    'Hardware not detected.',
                    style: TextStyle(color: Colors.redAccent),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        context,
                        'GPU',
                        hardwareService.hardwareInfo!.gpuName,
                      ),
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        context,
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
                child: _buildSettingsTextField(
                  context,
                  label: 'GPU Layers',
                  controller: state.gpuLayersController,
                  isNumber: true,
                  onChanged: (v) {
                    final val = int.tryParse(v);
                    if (val != null) storage.backendSettings.setGpuLayers(val);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSettingsTextField(
                  context,
                  label: 'Context Size',
                  controller: state.contextSizeController,
                  isNumber: true,
                  onChanged: (v) {
                    final val = int.tryParse(v);
                    if (val != null) {
                      storage.backendSettings.setContextSize(val);
                    }
                  },
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
                    value: storage.backendSettings.kvQuantizationLevel,
                    isExpanded: true,
                    dropdownColor: AppColors.surfaceContainerOf(context),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        storage.backendSettings.setKvQuantizationLevel(val);
                        state.notify();
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Text('0 - None (FP16)'),
                      ),
                      DropdownMenuItem(value: 1, child: Text('1 - 8-Bit Q8')),
                      DropdownMenuItem(value: 2, child: Text('2 - 4-Bit Q4')),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _applyAutoConfigure(context, state, storage),
                icon: const Icon(Icons.auto_fix_high, color: Colors.amber),
                label: const Text(
                  'Auto-Configure',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
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

  Widget _buildSettingsTextField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required bool isNumber,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: AppColors.textPrimary(context)),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
