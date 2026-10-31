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
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart' show formatRelativeTime;

/// What a restore of [kind] puts back, for the sentences below.
String restoreScope(PendingRestoreKind kind) => switch (kind) {
  PendingRestoreKind.full => 'library, settings and files',
  PendingRestoreKind.snapshot => 'library and settings',
  PendingRestoreKind.settings => 'settings',
};

/// Closes the app through its normal quit path (saves flushed, engines
/// stopped), so a restore staged for the next launch can run.
Future<void> quitToFinishRestore() async {
  try {
    await windowManager.close();
  } catch (e) {
    debugPrint('[Restore] could not close the window: $e');
  }
}

/// Asks the user to quit now so a staged restore can finish.
Future<void> showRestartToFinish(BuildContext context, DateTime created) {
  return showWarmDialog<void>(
    context,
    title: 'Restart to finish',
    icon: Icons.restart_alt_rounded,
    accent: AppColors.porchAmberOf(context),
    content: WarmDialogText(
      'The backup from ${formatRelativeTime(created)} is ready. It replaces '
      'your library, settings and files the next time you open Front Porch '
      'AI. A snapshot of everything as it is now was saved first, so you can '
      'go back.\n\nQuit now, then open the app again.',
    ),
    actions: [
      Builder(builder: (ctx) => warmDialogCancel(ctx, label: 'Later')),
      Builder(
        builder: (ctx) => warmDialogConfirm(
          ctx,
          label: 'Quit now',
          onPressed: () {
            Navigator.of(ctx).pop();
            quitToFinishRestore();
          },
        ),
      ),
    ],
  );
}

/// The notice after the first frame when this launch applied a restore.
Future<void> showRestoreOutcome(BuildContext context, RestoreOutcome o) {
  final what = 'Your ${restoreScope(o.kind)}';
  return showWarmDialog<void>(
    context,
    title: o.error == null ? 'Backup restored' : "The restore didn't finish",
    icon: o.error == null
        ? Icons.settings_backup_restore_rounded
        : Icons.warning_amber_rounded,
    content: WarmDialogText(
      o.error == null
          ? '$what are back to the backup from '
                '${formatRelativeTime(o.backupCreated)}.'
          : 'Front Porch AI could not restore the backup from '
                '${formatRelativeTime(o.backupCreated)}. The snapshot taken '
                'before the restore is on the Backups page.\n\n${o.error}',
    ),
    actions: [warmDialogCancel(context, label: 'OK')],
  );
}

/// Says when a restore is waiting for the next launch, with a way to drop
/// it. Shows nothing otherwise.
class PendingRestoreBanner extends StatefulWidget {
  const PendingRestoreBanner({super.key});

  @override
  State<PendingRestoreBanner> createState() => PendingRestoreBannerState();
}

class PendingRestoreBannerState extends State<PendingRestoreBanner> {
  late Future<PendingRestore?> _pending = BackupService.pendingRestore();

  void refresh() => setState(() => _pending = BackupService.pendingRestore());

  Future<void> _cancel() async {
    try {
      await BackupService.cancelPendingRestore();
    } catch (e) {
      debugPrint('[Restore] could not cancel the restore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel the restore: $e')),
        );
      }
    }
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PendingRestore?>(
      future: _pending,
      builder: (context, snap) {
        final pending = snap.data;
        if (pending == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final what = restoreScope(pending.kind);
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.porchAmberOf(context)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'A restore is waiting. Your $what go back to the backup from '
                '${formatRelativeTime(pending.created)} the next time you '
                'open Front Porch AI.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                ),
              ),
              TextButton(
                onPressed: quitToFinishRestore,
                child: const Text('Quit now'),
              ),
              TextButton(
                onPressed: _cancel,
                child: Text(
                  'Cancel restore',
                  style: TextStyle(color: AppColors.negativeAccentOf(context)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
