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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/backups/backup_restart.dart';
import 'package:front_porch_ai/ui/pages/backups/full_backup_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Backups & Restore: automatic snapshots (database plus settings) and full
/// backups to a file of the user's choosing (library, settings and the
/// user's own files). See [BackupService] and `lib/services/backup/`.
class BackupsPage extends StatefulWidget {
  const BackupsPage({super.key});

  @override
  State<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends State<BackupsPage> {
  late Future<List<BackupEntry>> _entries = BackupService.listEntries();
  final _pendingKey = GlobalKey<PendingRestoreBannerState>();

  void _refresh() {
    setState(() => _entries = BackupService.listEntries());
    _pendingKey.currentState?.refresh();
  }

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
          PendingRestoreBanner(key: _pendingKey),
          _sectionHeader(context, 'Automatic Snapshots'),
          const SizedBox(height: 8),
          _snapshotBody(context, theme),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Full Backup'),
          const SizedBox(height: 8),
          FullBackupCard(onChanged: _refresh),
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

  Widget _snapshotBody(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A snapshot of your library and settings is taken every 30 '
          'minutes. The newest ${BackupService.maxBackups} are always kept, '
          'plus one per day for the last ${BackupService.dailyRetentionDays} '
          'days. Snapshots stay on this computer; for a copy you can keep '
          'elsewhere, make a full backup below.',
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
              FutureBuilder<List<BackupEntry>>(
                future: _entries,
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
                    children: [
                      for (final b in backups) _backupTile(context, theme, b),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _time(DateTime t) =>
      '${t.month}/${t.day}/${t.year} '
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  Widget _backupTile(BuildContext context, ThemeData theme, BackupEntry b) {
    final sizeMb = (b.size / (1024 * 1024)).toStringAsFixed(1);
    final timeStr = _time(b.modified);
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
        b.hasSettings
            ? '$sizeMb MB · library and settings'
            : '$sizeMb MB · library only',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary(context),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _confirmRestore(context, b),
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
            onPressed: () => _confirmDelete(context, b, timeStr, sizeMb),
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
    _refresh();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    BackupEntry backup,
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
      await BackupService.deleteBackup(backup.file);
      if (!mounted) return;
      _refresh();
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

  void _confirmRestore(BuildContext context, BackupEntry backup) {
    var withSettings = backup.hasSettings;
    showWarmDialog<void>(
      context,
      title: 'Restore Backup?',
      icon: Icons.warning_amber_rounded,
      accent: AppColors.porchAmberOf(context),
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WarmDialogText(
              'This will replace your current database with the backup. '
              'All changes made after this backup was created will be lost.\n\n'
              'Your library reloads in place, so you should not need to restart.',
            ),
            if (backup.hasSettings)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: withSettings,
                onChanged: (v) => setLocal(() => withSettings = v ?? false),
                title: const Text('Also restore settings'),
                subtitle: const Text(
                  'Saved prompts, presets and every other setting come back '
                  'the next time you open Front Porch AI.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        Builder(builder: (ctx) => warmDialogCancel(ctx)),
        Builder(
          builder: (ctx) => warmDialogConfirm(
            ctx,
            label: 'Restore',
            onPressed: () => _restore(ctx, backup, withSettings),
          ),
        ),
      ],
    );
  }

  Future<void> _restore(
    BuildContext dialogContext,
    BackupEntry backup,
    bool withSettings,
  ) async {
    Navigator.of(dialogContext).pop();
    try {
      await BackupService.restoreBackup(backup.file.path);
      if (!mounted) return;
      // Reopening the database is not enough on its own: every repository and
      // service captured the instance restoreBackup just closed, so without the
      // rebind the app looked restored but threw "database was closed" on the
      // next action. Never cleans orphaned portraits — an older snapshot is
      // *supposed* to be missing newer characters.
      final rebound = await reopenAndRebindDatabase(context);
      // Settings cannot be swapped under a running app (every service holds
      // the old values), so they wait for the next launch.
      var settingsStaged = false;
      if (withSettings) {
        try {
          await BackupService.stageSnapshotSettings(backup);
          settingsStaged = true;
        } catch (e) {
          debugPrint('[Backup] could not stage settings: $e');
        }
      }
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: settingsStaged ? 10 : 4),
          action: settingsStaged
              ? SnackBarAction(
                  label: 'Quit now',
                  onPressed: quitToFinishRestore,
                )
              : null,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rebound != null
                    ? 'Backup restored. Your library is back to that snapshot.'
                    : 'Backup restored to disk, but the app could not reload it — '
                          'please close and reopen Front Porch AI.',
              ),
              if (settingsStaged)
                const Text(
                  'Your settings come back the next time you open '
                  'Front Porch AI.',
                ),
              if (withSettings && !settingsStaged)
                const Text(
                  "The settings in that backup couldn't be read, so your "
                  'current settings stay.',
                ),
            ],
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
