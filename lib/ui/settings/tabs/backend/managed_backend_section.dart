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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/dialogs/generate_kcpps_dialog.dart';

/// Local managed-KoboldCPP section: backend download/version, auto-start,
/// model selection, vision projector, .kcpps preset selection, config
/// generation, start/stop, and process logs. Extracted from settings_page's
/// Backend tab.
///
/// The intricate, state-mutating callbacks (model selection, preset wiring,
/// launch) stay in the page's State and are passed in verbatim — this widget
/// only renders and forwards, so the launch behavior is unchanged. AppColors +
/// warm-porch accents.
class ManagedBackendSection extends StatelessWidget {
  const ManagedBackendSection({
    super.key,
    required this.selectedModelPath,
    required this.localPresets,
    required this.onModelSelected,
    required this.onVisionChanged,
    required this.onScanPresets,
    required this.onKcppsChanged,
    required this.onKcppsExternalClear,
    required this.onKcppsBrowsePicked,
    required this.onKcppsModelStatusChanged,
    required this.onGenerateKcppsDone,
    required this.onToggleBackend,
  });

  final String? selectedModelPath;
  final List<File> localPresets;
  final ValueChanged<String?> onModelSelected;
  final VoidCallback onVisionChanged;
  final VoidCallback onScanPresets;
  final ValueChanged<String?> onKcppsChanged;
  final VoidCallback onKcppsExternalClear;
  final ValueChanged<String> onKcppsBrowsePicked;
  final ValueChanged<bool> onKcppsModelStatusChanged;
  final VoidCallback onGenerateKcppsDone;
  final VoidCallback onToggleBackend;

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final backendManager = Provider.of<BackendManager>(context);
    final koboldService = Provider.of<KoboldService>(context);
    final theme = Theme.of(context);

    final anyRunning = koboldService.isRunning || koboldService.isStarting;
    final canStart =
        (storageService.kcppsHasModel && storageService.kcppsModelFileExists) ||
        selectedModelPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('Koboldcpp Backend'),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (backendManager.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  backendManager.error!,
                  style: TextStyle(color: AppColors.negativeAccentOf(context)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backendManager.backendPath != null
                            ? 'Status: Ready${backendManager.localVersionDisplay.isNotEmpty ? ' (${backendManager.localVersionDisplay})' : ''}'
                            : 'Status: Missing',
                        style: TextStyle(
                          color: backendManager.backendPath != null
                              ? AppColors.bondHighOf(context)
                              : AppColors.taskAccentOf(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (backendManager.backendPath != null)
                        Text(
                          backendManager.backendPath!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (backendManager.isDownloading ||
                    backendManager.isCheckingVersion)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  ElevatedButton(
                    onPressed: backendManager.backendPath == null
                        ? () => backendManager.downloadBackend()
                        : backendManager.versionError != null ||
                              backendManager.remoteVersion == null
                        ? () => backendManager.checkForUpdates()
                        : backendManager.isUpdateAvailable
                        ? () => backendManager.downloadBackend()
                        : null,
                    child: Text(
                      backendManager.backendPath == null
                          ? 'Download'
                          : backendManager.versionError != null
                          ? 'Check (failed)'
                          : backendManager.remoteVersion == null
                          ? 'Check for Updates'
                          : backendManager.isUpdateAvailable
                          ? 'Update to v${backendManager.remoteVersion}'
                          : 'Up to date',
                    ),
                  ),
              ],
            ),
            if (backendManager.isDownloading)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: LinearProgressIndicator(
                  value: backendManager.downloadProgress,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SwitchListTile(
            title: const Text(
              'Auto-start model on launch',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              'Automatically load the last used model when the app starts',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
            value: storageService.autostartBackend,
            activeTrackColor: AppColors.porchAmberOf(context),
            onChanged: (val) {
              storageService.setAutostartBackend(val);
            },
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader('Model Selection'),
        const SizedBox(height: 16),
        ModelSelector(
          models: modelManager.models,
          selectedModelPath: selectedModelPath,
          showManagedByKcpps:
              storageService.kcppsHasModel &&
              storageService.kcppsModelFileExists,
          onChanged: onModelSelected,
        ),
        // Vision projector (mmproj) for the selected model — the same
        // field the chat Model Settings dialog shows, surfaced here too
        // because this page is where users actually pick the model.
        // Self-hides when a preset owns the model; greys out for
        // text-only / vision-built-in GGUFs. Applied on next start.
        const SizedBox(height: 12),
        VisionProjectorField(
          modelPath: selectedModelPath,
          storage: storageService,
          onChanged: onVisionChanged,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader('Configuration Preset'),
            TextButton.icon(
              onPressed: onScanPresets,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Rescan', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textTertiary(context),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        KcppsSelector(
          storage: storageService,
          localPresets: localPresets,
          hint: 'None (Use App Settings)',
          onChanged: onKcppsChanged,
          onExternalClear: onKcppsExternalClear,
          onBrowsePicked: onKcppsBrowsePicked,
          onModelStatusChanged: onKcppsModelStatusChanged,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (_) => const GenerateKcppsDialog(),
              );
              if (result == true) onGenerateKcppsDone();
            },
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Generate KCPPS Config...'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
              side: BorderSide(color: AppColors.borderOf(context)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Button enabled when: backend path exists AND
        // (kcpps has valid model OR model selected manually).
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: anyRunning
                ? onToggleBackend
                : backendManager.backendPath == null || !canStart
                ? null
                : onToggleBackend,
            icon: Icon(anyRunning ? Icons.stop : Icons.play_arrow),
            label: Text(anyRunning ? 'Stop Backend' : 'Start Backend'),
            style: ElevatedButton.styleFrom(
              backgroundColor: anyRunning
                  ? AppColors.negativeAccentOf(context).withValues(alpha: 0.85)
                  : AppColors.bondHighOf(context).withValues(alpha: 0.85),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader('Process Logs'),
        const SizedBox(height: 8),
        Consumer<KoboldService>(
          builder: (context, ks, child) => LogView(logs: ks.logs),
        ),
      ],
    );
  }
}
