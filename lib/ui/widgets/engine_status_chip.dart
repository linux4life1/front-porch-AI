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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The corner status chip for the managed KoboldCpp engine — the visible half
/// of the background-download first-launch flow (the app opens instantly; the
/// engine arrives quietly). Mounted once over the page area in MainLayout so
/// it's visible on every screen. Three states, else invisible:
/// - downloading: live progress (%, speed, ETA from BackendManager).
/// - failed: the error with a Retry.
/// - missing (managed-engine choice made, binary absent, nothing running):
///   a "Download" affordance — the durable "install it later" entry point.
/// Hidden entirely for remote/own-backend users and on Intel Macs.
class EngineStatusChip extends StatelessWidget {
  const EngineStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<BackendManager, StorageService>(
      builder: (context, backend, storage, _) {
        final backendType = storage.backendSettings.backendType;
        if (backendType == 'openRouter' || backendType == 'omlx') {
          return const SizedBox.shrink();
        }
        if (backend.isIntelMac) return const SizedBox.shrink();
        if (!storage.backendSettings.backendChoiceDone) {
          return const SizedBox.shrink();
        }

        if (backend.isDownloading) {
          return _card(
            context,
            icon: Icons.downloading,
            title: 'Downloading AI engine',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: backend.downloadProgress > 0
                        ? backend.downloadProgress
                        : null,
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.porchAmberOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  backend.statusMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          );
        }

        if (backend.backendPath != null) return const SizedBox.shrink();

        final failed = backend.error != null;
        return _card(
          context,
          icon: failed ? Icons.error_outline : Icons.download_for_offline,
          title: failed ? 'Engine download failed' : 'AI engine not installed',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                failed
                    ? backend.error!
                    : 'Needed to run models on this computer.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textTertiary(context),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () => backend.ensureEngineInstalled(),
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(failed ? 'Retry' : 'Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onChaosAccent,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget body,
  }) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: AppColors.cardOf(context),
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.porchAmberOf(context).withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.porchAmberOf(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
            body,
          ],
        ),
      ),
    );
  }
}
