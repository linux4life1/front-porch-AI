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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'kobold_preset_section.dart';

/// The local (KoboldCpp) backend's settings panel: model dropdown, vision
/// projector field, preset picker with the launch fields it overrides, and
/// the Start-Restart button.
class LocalBackendSettings extends StatelessWidget {
  const LocalBackendSettings({
    super.key,
    required this.storage,
    required this.models,
    required this.selectedModelPath,
    required this.showManagedByKcpps,
    required this.hardware,
    required this.koboldRunning,
    required this.localPresets,
    required this.gpuLayersController,
    required this.contextSizeController,
    required this.onModelChanged,
    required this.onChoosePreset,
    required this.onBrowsePicked,
    required this.onRefresh,
    required this.onRestart,
  });

  final StorageService storage;
  final List<FileSystemEntity> models;
  final String? selectedModelPath;
  final bool showManagedByKcpps;
  final HardwareService hardware;
  final bool koboldRunning;
  final List<File> localPresets;
  final TextEditingController gpuLayersController;
  final TextEditingController contextSizeController;
  final ValueChanged<String?> onModelChanged;
  final Future<void> Function(String? path) onChoosePreset;
  final Future<void> Function(String path) onBrowsePicked;

  /// Something the panel changed needs the dialog to rebuild.
  final VoidCallback onRefresh;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final isPresetActive =
        storage.backendSettings.activeKcppsPath != null &&
        storage.backendSettings.activeKcppsPath!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LowPerfCpuWarning(margin: EdgeInsets.only(bottom: 12)),
        ModelSelector(
          models: models,
          selectedModelPath: selectedModelPath,
          showManagedByKcpps: showManagedByKcpps,
          onChanged: onModelChanged,
        ),

        // Vision projector (mmproj) — only meaningful for a concrete local GGUF;
        // the field self-hides when no model file is selected (a preset owns it)
        // and greys out for text-only / vision-built-in models.
        VisionProjectorField(
          modelPath: selectedModelPath,
          storage: storage,
          onChanged: onRefresh,
        ),

        const SizedBox(height: 16),

        KoboldPresetSection(
          localPresets: localPresets,
          hardware: hardware,
          gpuLayersController: gpuLayersController,
          contextSizeController: contextSizeController,
          onChoosePreset: onChoosePreset,
          onBrowsePicked: onBrowsePicked,
          onRefresh: onRefresh,
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh),
            label: Text(
              isPresetActive
                  ? (koboldRunning
                        ? 'Restart with Preset'
                        : 'Start with Preset')
                  : (koboldRunning ? 'Restart Backend' : 'Start Backend'),
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
}
