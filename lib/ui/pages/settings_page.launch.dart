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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'package:front_porch_ai/ui/pages/settings_page/launch_actions.dart';
import 'package:front_porch_ai/ui/pages/settings_page/launch_engine_rows.dart';

/// Collapsible "Advanced Launch Options" of the Advanced tab: the engine rows
/// ([launchEngineRows]), GPU ID, BLAS batch size, idle unload, recent chats,
/// and the restart-backend action. Warm-porch amber accent.
///
/// The expanded flag is owned by the page so it survives tab switches.
/// This library stays at this path because
/// test/ui/pages/settings_page_launch_state_test.dart reads it.
class AdvancedLaunchOptions extends StatelessWidget {
  const AdvancedLaunchOptions({
    super.key,
    required this.storage,
    required this.expanded,
    required this.onToggleExpanded,
    required bool Function(String? path) launchModelExists,
    required this.onRocmChanged,
  }) : _launchModelExists = launchModelExists;

  final StorageService storage;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Does the model the backend would relaunch still exist? Must be memoized
  /// per path: the restart button's Builder listens to KoboldService, which
  /// notifies per backend log line while a model loads, and a bare existsSync
  /// there stats a multi-GB GGUF on every one of those rebuilds.
  final bool Function(String? path) _launchModelExists;

  final VoidCallback onRocmChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          // Header — tap to expand/collapse.
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.tune, color: accent, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Advanced Launch Options',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    'Affects next restart',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.iconSecondary(context),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: _buildBody(context, accent),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 12),
          ...launchEngineRows(
            context,
            storage: storage,
            accent: accent,
            onRocmChanged: onRocmChanged,
          ),
          const SizedBox(height: 12),
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 12),
          // GPU ID selector.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GPU ID',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Which GPU to use for CUDA. Set to 1+ on systems with both a discrete and an integrated GPU.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 6,
                children: [0, 1, 2, 3].map((id) {
                  final isSelected = storage.backendSettings.gpuId == id;
                  return GestureDetector(
                    onTap: () => storage.backendSettings.setGpuId(id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent
                            : AppColors.textPrimary(
                                context,
                              ).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : AppColors.borderOf(context),
                        ),
                      ),
                      child: Text(
                        '$id',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isSelected
                              ? AppColors.onChaosAccent
                              : AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // BLAS Batch Size.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prefill Batch Size',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tokens processed in parallel during prompt evaluation. Higher = faster context loading, more VRAM. Auto uses 1,024 on NVIDIA cards and 512 elsewhere, or what the speed test found fastest, never more than keeps the model on the card.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 6,
                // 0 is Auto: the launch picks the batch for this machine.
                children: [0, 256, 512, 1024, 2048, 4096, 8192].map((bs) {
                  final b = storage.backendSettings;
                  final isSelected = bs == 0
                      ? b.batchAutomatic
                      : !b.batchAutomatic && b.blasBatchSize == bs;
                  return GestureDetector(
                    onTap: () async {
                      await b.setBatchAutomatic(bs == 0);
                      if (bs != 0) await b.setBlasBatchSize(bs);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent
                            : AppColors.textPrimary(
                                context,
                              ).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : AppColors.borderOf(context),
                        ),
                      ),
                      child: Text(
                        bs == 0
                            ? 'Auto'
                            : bs >= 1024
                            ? '${bs ~/ 1024}K'
                            : '$bs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isSelected
                              ? AppColors.onChaosAccent
                              : AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          KoboldIdleUnloadRow(
            settings: storage.backendSettings,
            accent: accent,
          ),
          const SizedBox(height: 16),
          KoboldKeepRecentRow(
            settings: storage.backendSettings,
            accent: accent,
          ),
          const SizedBox(height: 14),
          // Restart button — applies all Advanced Launch changes immediately.
          Builder(
            builder: (ctx) {
              final koboldService = Provider.of<KoboldService>(
                ctx,
                listen: true,
              );
              final backendManager = Provider.of<BackendManager>(
                ctx,
                listen: false,
              );
              final storage = Provider.of<StorageService>(ctx, listen: false);
              // Chat on another backend: the options do not reach it, so no
              // Start button and no "pick a model" blame.
              final canRestart =
                  launchOptionsApply(storage) &&
                  backendManager.backendPath != null &&
                  _launchModelExists(storage.backendSettings.lastUsedModelPath);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canRestart)
                    LaunchOptionsNotice(
                      text: launchOptionsNoticeText(storage),
                      accent: accent,
                    ),
                  if (canRestart)
                    ElevatedButton.icon(
                      onPressed: () => restartFromLaunchOptions(ctx),
                      icon: Icon(
                        koboldService.isRunning
                            ? Icons.restart_alt
                            : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(
                        koboldService.isRunning
                            ? 'Restart Backend'
                            : 'Start Backend',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: AppColors.onChaosAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
