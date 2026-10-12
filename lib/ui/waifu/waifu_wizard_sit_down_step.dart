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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_honesty_text.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mode_chips.dart';
import 'package:front_porch_ai/ui/waifu/waifu_scope_badge.dart';

class WaifuWizardSitDownStep extends StatelessWidget {
  const WaifuWizardSitDownStep({
    super.key,
    required this.folderPath,
    required this.coworker,
    required this.backendLabel,
    required this.isLocalBackend,
    required this.toolsSupported,
    required this.mode,
    required this.pathMode,
    required this.honestyAccepted,
    required this.onModeChanged,
    required this.onPathModeChanged,
    required this.onHonestyChanged,
    required this.onConfirm,
    this.skipHonestyQuiz = false,
    this.starting = false,
    this.startError,
  });

  final String folderPath;
  final CharacterCard? coworker;
  final String backendLabel;
  final bool isLocalBackend;
  final bool toolsSupported;
  final WaifuMode mode;
  final WaifuPathMode pathMode;
  final bool honestyAccepted;
  final ValueChanged<WaifuMode> onModeChanged;
  final ValueChanged<WaifuPathMode> onPathModeChanged;
  final ValueChanged<bool> onHonestyChanged;
  final VoidCallback onConfirm;
  final bool skipHonestyQuiz;

  /// Start was pressed and the session is being prepared.
  final bool starting;

  /// Why the last Start failed, shown under the button.
  final String? startError;

  bool get hideHonesty => skipHonestyQuiz && honestyAccepted;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final can = waifuCanSitDown(
      honestyAccepted: honestyAccepted,
      toolsSupported: toolsSupported,
      hasFolder: folderPath.isNotEmpty,
      hasCoworker: coworker != null,
    );
    final honey = AppColors.porchHoneyOf(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pull up a chair',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    amber.withValues(alpha: 0.28),
                    honey.withValues(alpha: 0.12),
                    AppColors.cardOf(context),
                  ],
                ),
                border: Border.all(color: amber.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: amber.withValues(alpha: 0.22),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Folder: $folderPath',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  Text(
                    'Coworker: ${coworker?.name ?? '—'}',
                    style: TextStyle(color: honey, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Backend: ${backendLabel.isEmpty ? 'current Settings backend' : backendLabel}',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      WaifuModeBadge(
                        key: const Key('waifu-sit-down-mode'),
                        mode: mode,
                      ),
                      WaifuScopeBadge(
                        key: const Key('waifu-sit-down-scope'),
                        pathMode: pathMode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Where can they work?',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            WaifuScopeChips(pathMode: pathMode, onChanged: onPathModeChanged),
            const SizedBox(height: 8),
            Text(
              waifuPathModeBlurb(pathMode),
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 16),
            Text(
              'Mode',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            WaifuModeChips(mode: mode, onChanged: onModeChanged),
            const SizedBox(height: 8),
            Text(
              waifuModeTooltip(mode),
              key: const Key('waifu-mode-explained'),
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            if (mode == WaifuMode.yolo) ...[
              const SizedBox(height: 8),
              Text(
                waifuYoloWarning(pathMode),
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ],
            if (isLocalBackend) ...[
              const SizedBox(height: 12),
              Text(
                kWaifuLocalModelWarning,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ],
            if (!toolsSupported) ...[
              const SizedBox(height: 12),
              Text(
                kWaifuToolsUnsupported,
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
            ],
            if (!hideHonesty) ...[
              const SizedBox(height: 20),
              WaifuHonestyText(text: waifuHonestyBody(pathMode)),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('waifu-honesty-checkbox'),
                value: honestyAccepted,
                onChanged: (v) => onHonestyChanged(v ?? false),
                title: Text(waifuHonestyCheckbox(pathMode)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ] else ...[
              const SizedBox(height: 16),
              Text(
                kWaifuHonestySkipped,
                key: const Key('waifu-honesty-skipped'),
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                key: const Key('waifu-sit-down-confirm'),
                onPressed: can && !starting ? onConfirm : null,
                icon: starting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          key: const Key('waifu-starting'),
                          strokeWidth: 2,
                          color: AppColors.textSecondary(context),
                        ),
                      )
                    : const Icon(Icons.bolt_rounded),
                label: Text(starting ? 'Starting…' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: amber,
                  foregroundColor: AppColors.onChaosAccent,
                  disabledBackgroundColor: AppColors.surfaceContainerOf(
                    context,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            if (startError != null) ...[
              const SizedBox(height: 8),
              Text(
                startError!,
                key: const Key('waifu-start-error'),
                style: TextStyle(color: AppColors.negativeAccentOf(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
