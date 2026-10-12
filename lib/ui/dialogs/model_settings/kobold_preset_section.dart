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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_lib;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'local_backend_actions.dart';
import 'model_settings_text_field.dart';

/// The local backend's preset picker and the launch fields it overrides:
/// hardware info, GPU layers, context size and KV quantization. The fields
/// fade and stop taking input while a preset is active.
class KoboldPresetSection extends StatelessWidget {
  const KoboldPresetSection({
    super.key,
    required this.localPresets,
    required this.hardware,
    required this.gpuLayersController,
    required this.contextSizeController,
    required this.onChoosePreset,
    required this.onBrowsePicked,
    required this.onRefresh,
  });

  final List<File> localPresets;
  final HardwareService hardware;
  final TextEditingController gpuLayersController;
  final TextEditingController contextSizeController;

  /// A preset was chosen from the list, or none when null.
  final Future<void> Function(String? path) onChoosePreset;

  /// A preset file was picked with Browse.
  final Future<void> Function(String path) onBrowsePicked;

  /// Something this section changed needs the dialog to rebuild.
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
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
              localPresets: localPresets,
              hint: 'None (Use App Settings)',
              onChanged: onChoosePreset,
              onExternalClear: () => onChoosePreset(null),
              onBrowsePicked: onBrowsePicked,
              onModelStatusChanged: (_) {
                onRefresh();
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
                    color: AppColors.formMasterAccent.withValues(alpha: 0.3),
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
                      child: hardware.isDetecting
                          ? const Center(child: CircularProgressIndicator())
                          : hardware.hardwareInfo == null
                          ? const Text(
                              'Hardware not detected.',
                              // theme-keep: detection-error text
                              style: TextStyle(color: Colors.redAccent),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HardwareInfoRow(
                                  label: 'GPU',
                                  value: hardware.hardwareInfo!.gpuName,
                                ),
                                HardwareInfoRow(
                                  label: 'VRAM',
                                  value:
                                      '${hardware.hardwareInfo!.vramMb} MB${hardware.hardwareInfo!.isSharedMemory ? ' (Shared)' : ''}',
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),

                    GpuLayersField(
                      dense: true,
                      manual: storage.backendSettings.gpuLayersManual,
                      retiredLayers: storage.backendSettings.retiredGpuLayers,
                      onDismissRetired:
                          storage.backendSettings.dismissGpuLayersNote,
                      controller: gpuLayersController,
                      onManualChanged: (v) {
                        Provider.of<StorageService>(
                          context,
                          listen: false,
                        ).backendSettings.setGpuLayersManual(v);
                        onRefresh();
                      },
                      onLayersChanged: (text) =>
                          saveGpuLayersText(storage, text),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PresetContextLock(
                            locked: storage.backendSettings.presetOwnsContext,
                            child: ModelSettingsTextField(
                              label: 'Context Size',
                              controller: contextSizeController,
                              isNumber: true,
                              onChanged: (text) =>
                                  saveContextSizeText(storage, text),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: contextSizeController,
                      builder: (context, value, _) => ContextSizeWarnings(
                        contextSize: int.tryParse(value.text),
                        maxOutput: storage.generationSettings.maxLength,
                      ),
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
                          child: KvQuantPicker(
                            value: Provider.of<StorageService>(
                              context,
                            ).backendSettings.kvQuant,
                            onChanged: (val) {
                              Provider.of<StorageService>(
                                context,
                                listen: false,
                              ).backendSettings.setKvQuant(val);
                              onRefresh();
                            },
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
    );
  }
}

/// One label/value line of the hardware info box.
class HardwareInfoRow extends StatelessWidget {
  const HardwareInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
