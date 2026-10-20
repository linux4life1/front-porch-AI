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

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Local database Backups & Restore.
///
/// Extracted from the (removed) Cloud Sync page so the local-backup feature
/// lives on its own — it was never cloud-dependent (it's driven entirely by
/// the on-device [BackupService]).
class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Backups & Restore'),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionHeader(context, 'Database Backups'),
          const SizedBox(height: 8),
          if (isPreRelease)
            _disabledNotice(context, theme)
          else
            _backupBody(context, theme),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary(context),
      ),
    );
  }

  Widget _disabledNotice(BuildContext context, ThemeData theme) {
    final accent = AppColors.porchAmberOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.backup, size: 48, color: accent.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            'Backups Disabled',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Database backups are disabled in nightly builds to prevent '
            'confusion between nightly and stable databases. Backups will be '
            're-enabled once $stableVersionBase goes stable.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: accent,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _backupBody(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Backups are created automatically every 30 minutes. The newest '
          '${BackupService.maxBackups} are always kept, plus one per day for the '
          'last ${BackupService.dailyRetentionDays} days — fine-grained recent '
          'history and a rolling week of daily restore points.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _createBackup,
                  icon: const Icon(Icons.backup, size: 18),
                  label: const Text('Create Backup Now'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onAccentOf(context),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<File>>(
                future: BackupService.listBackups(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final backups = snapshot.data ?? [];
                  if (backups.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No backups yet. One is created automatically every 30 '
                        'minutes, or make one now with the button above.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return Column(
                    children: backups
                        .map((b) => _backupTile(context, theme, b))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _backupTile(BuildContext context, ThemeData theme, File backup) {
    final stat = backup.statSync();
    final sizeMb = (stat.size / (1024 * 1024)).toStringAsFixed(1);
    final modified = stat.modified.toLocal();
    final timeStr =
        '${modified.month}/${modified.day}/${modified.year} '
        '${modified.hour}:${modified.minute.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.storage,
        size: 20,
        color: AppColors.porchAmberOf(context),
      ),
      title: Text(
        timeStr,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary(context),
        ),
      ),
      subtitle: Text(
        '$sizeMb MB',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary(context),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _confirmRestore(context, backup.path),
            child: Text(
              'Restore',
              style: TextStyle(color: AppColors.porchAmberOf(context)),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: AppColors.negativeAccentOf(context),
            ),
            tooltip: 'Delete backup',
            onPressed: () => _confirmDelete(context, backup, timeStr, sizeMb),
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    final path = await BackupService.createBackup();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null
              ? 'Backup created successfully'
              : 'Backup could not be created — the database may be busy or '
                    'the disk full. Try again in a moment.',
        ),
      ),
    );
    setState(() {}); // refresh the list
  }

  Future<void> _confirmDelete(
    BuildContext context,
    File backup,
    String timeStr,
    String sizeMb,
  ) async {
    // The buttons pop with the dialog's own context (Builder): the page's
    // context can belong to a different navigator than the dialog's.
    final confirmed = await showWarmDialog<bool>(
      context,
      title: 'Delete Backup?',
      destructive: true,
      content: WarmDialogText(
        'Delete backup from $timeStr ($sizeMb MB)?\n\nThis cannot be undone.',
      ),
      actions: [
        Builder(builder: (ctx) => warmDialogCancel(ctx, value: false)),
        Builder(
          builder: (ctx) => warmDialogConfirm(
            ctx,
            label: 'Delete',
            destructive: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );
    if (confirmed != true) return;
    try {
      await backup.delete();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _confirmRestore(BuildContext context, String backupPath) {
    showWarmDialog<void>(
      context,
      title: 'Restore Backup?',
      icon: Icons.warning_amber_rounded,
      accent: AppColors.porchAmberOf(context),
      content: const WarmDialogText(
        'This will replace your current database with the backup. '
        'All changes made after this backup was created will be lost.\n\n'
        'Your library reloads in place, so you should not need to restart.',
      ),
      actions: [
        Builder(builder: (ctx) => warmDialogCancel(ctx)),
        Builder(
          builder: (ctx) => warmDialogConfirm(
            ctx,
            label: 'Restore',
            onPressed: () => _restore(ctx, backupPath),
          ),
        ),
      ],
    );
  }

  Future<void> _restore(BuildContext dialogContext, String backupPath) async {
    Navigator.of(dialogContext).pop();
    try {
      await BackupService.restoreBackup(backupPath);
      if (!mounted) return;
      // Reopening the database is not enough on its own: every repository and
      // service captured the instance restoreBackup just closed, so without the
      // rebind the app looked restored but threw "database was closed" on the
      // next action. Never cleans orphaned portraits — an older snapshot is
      // *supposed* to be missing newer characters.
      final rebound = await reopenAndRebindDatabase(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rebound != null
                ? 'Backup restored. Your library is back to that snapshot.'
                : 'Backup restored to disk, but the app could not reload it — '
                      'please close and reopen Front Porch AI.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }
}
