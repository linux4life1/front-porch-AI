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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One glanceable connection card for the local image backends: state icon,
/// a plain-words line ("Connected — 12 models · 4 LoRAs" / a per-backend
/// "is it running?" hint), and a Retry button. Replaces the scattered
/// per-backend Test buttons + status icons — the tab auto-tests on open and
/// on backend switch, so novices never have to know a Test step exists.
class ConnectionStatusCard extends StatelessWidget {
  final String backendLabel;

  /// null = not tested yet (or in flight when [testing]).
  final bool? connected;
  final bool testing;
  final int modelCount;
  final int loraCount;

  /// Shown when unreachable, e.g. "Is ComfyUI running? It listens on
  /// http://127.0.0.1:8188 by default."
  final String notReachableHint;
  final VoidCallback onRetry;

  const ConnectionStatusCard({
    super.key,
    required this.backendLabel,
    required this.connected,
    required this.testing,
    required this.modelCount,
    required this.loraCount,
    required this.notReachableHint,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent;
    final Widget icon;
    final String headline;
    final String? detail;
    if (testing) {
      accent = AppColors.formMasterAccent;
      icon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.formMasterAccent,
        ),
      );
      headline = 'Checking $backendLabel…';
      detail = null;
    } else if (connected == true) {
      accent = AppColors.logReady;
      icon = const Icon(
        Icons.check_circle,
        size: 18,
        color: AppColors.logReady,
      );
      headline = '$backendLabel connected';
      detail = modelCount > 0
          ? '$modelCount model${modelCount == 1 ? '' : 's'}'
                '${loraCount > 0 ? ' · $loraCount LoRA${loraCount == 1 ? '' : 's'}' : ''}'
          : 'No models reported — check the server\'s model folder.';
    } else if (connected == false) {
      accent = AppColors.logError;
      icon = const Icon(
        Icons.error_outline,
        size: 18,
        color: AppColors.logError,
      );
      headline = '$backendLabel not reachable';
      detail = notReachableHint;
    } else {
      accent = AppColors.formMasterAccent;
      icon = Icon(
        Icons.wifi_tethering,
        size: 18,
        color: AppColors.iconSecondary(context),
      );
      headline = 'Not checked yet';
      detail = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (!testing)
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(
                Icons.refresh,
                size: 14,
                color: AppColors.iconSecondary(context),
              ),
              label: Text(
                connected == true ? 'Refresh' : 'Retry',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
            ),
        ],
      ),
    );
  }
}
