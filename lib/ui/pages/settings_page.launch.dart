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

/// Collapsible "Advanced Launch Options" of the Advanced tab: Flash Attention,
/// mlock, GPU ID, BLAS batch size, and the restart-backend action. Extracted
/// from the inline _buildAdvancedLaunchOptions/_Body; direct state access
/// preserves behavior. Warm-porch amber accent (was a teal-green literal).
extension _SettingsLaunchOptions on _SettingsPageState {
  /// Does the model the backend would relaunch still exist? Memoized per
  /// path: the caller's Builder listens to KoboldService, which notifies per
  /// backend log line while a model loads, and a bare existsSync there stats
  /// a multi-GB GGUF on every one of those rebuilds.
  bool _launchModelExists(String? path) {
    if (path == null) return false;
    if (_launchModelExistsForPath == path) return _launchModelExistsCache;
    _launchModelExistsForPath = path;
    _launchModelExistsCache = File(
      path,
    ).existsSync(); // io-ok: memoized per path — once per model, not per notify
    return _launchModelExistsCache;
  }

  /// The Start/Restart button under Advanced Launch Options: applies the
  /// launch settings above by starting the engine again.
  Future<void> _restartFromLaunchOptions(BuildContext ctx) async {
    final koboldService = Provider.of<KoboldService>(ctx, listen: false);
    final backendManager = Provider.of<BackendManager>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final messenger = ScaffoldMessenger.of(ctx);

    // Checked before anything is stopped, so a model or preset that cannot
    // be used leaves the running engine alone.
    final problem = await koboldLaunchProblem(storage);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    final wasRunning = koboldService.isRunning;
    if (wasRunning) {
      await koboldService.stopKobold();
      await Future.delayed(const Duration(seconds: 1));
    }
    final result = await koboldService.launch(backendManager.backendPath!);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.message ??
              (wasRunning
                  ? 'Restarting backend with new settings…'
                  : 'Starting backend…'),
        ),
      ),
    );
  }

  Widget _buildAdvancedLaunchOptions(
    BuildContext context,
    StorageService storage,
  ) {
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
            onTap: () => rebuildState(
              () => _advancedLaunchExpanded = !_advancedLaunchExpanded,
            ),
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
                    turns: _advancedLaunchExpanded ? 0.5 : 0,
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
            secondChild: _buildAdvancedLaunchBody(context, storage, accent),
            crossFadeState: _advancedLaunchExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedLaunchBody(
    BuildContext context,
    StorageService storage,
    Color accent,
  ) {
    Widget toggle({
      required String label,
      required String tooltip,
      required bool value,
      required ValueChanged<bool> onChanged,
      bool recommended = false,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              fontSize: 9,
                              color: accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tooltip,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: accent,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 12),
          toggle(
            label: 'Flash Attention',
            tooltip:
                'Faster attention math. ~20–40% speed boost on RTX/Apple Silicon. Disabled automatically for ROCm.',
            value: storage.backendSettings.flashAttentionEnabled,
            recommended: true,
            onChanged: (v) =>
                storage.backendSettings.setFlashAttentionEnabled(v),
          ),
          toggle(
            label: 'Lock Weights in RAM (mlock)',
            tooltip: Platform.isLinux
                ? 'Prevents paging to disk. Requires root or ulimit ‑l unlimited on Linux — off by default.'
                : 'Prevents OS from paging model weights to disk. Avoids catastrophic slowdown under memory pressure.',
            value: storage.backendSettings.mlockEnabled,
            recommended: !Platform.isLinux,
            onChanged: (v) => storage.backendSettings.setMlockEnabled(v),
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
                      'Tokens processed in parallel during prompt evaluation. Higher = faster context loading, more VRAM. Auto picks the largest that keeps the model on the card.',
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
              final canRestart =
                  backendManager.backendPath != null &&
                  _launchModelExists(storage.backendSettings.lastUsedModelPath);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canRestart)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: accent, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No model loaded yet. Select a model on the Backend tab first.',
                              style: TextStyle(fontSize: 11, color: accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (canRestart)
                    ElevatedButton.icon(
                      onPressed: () => _restartFromLaunchOptions(ctx),
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
