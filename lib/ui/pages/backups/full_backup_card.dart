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

import 'package:front_porch_ai/services/backup/backup_manifest.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/backup_service.dart';
import 'package:front_porch_ai/ui/pages/backups/backup_restart.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';
import 'package:front_porch_ai/utils/utils.dart' show formatRelativeTime;

/// Full backup to a file the user keeps anywhere, and restore from one.
class FullBackupCard extends StatefulWidget {
  const FullBackupCard({super.key, required this.onChanged});

  /// Called after a restore was staged, so the page can show the banner.
  final VoidCallback onChanged;

  @override
  State<FullBackupCard> createState() => _FullBackupCardState();
}

class _FullBackupCardState extends State<FullBackupCard> {
  bool _includeSecrets = false;
  bool _busy = false;
  double? _progress;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final folder = await GuardedPicker.getDirectoryPath(
      context,
      category: PickerPrefs.catExport,
      dialogTitle: 'Choose where to save the backup',
    );
    if (folder == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final out = await BackupService.createFullBackup(
        folder,
        includeSecrets: _includeSecrets,
        onFile: (done, total) {
          // One repaint per percent, not one per file.
          final next = (done * 100 ~/ total) / 100;
          if (mounted && next != _progress) setState(() => _progress = next);
        },
      );
      _snack('Full backup saved to $out');
    } catch (e) {
      debugPrint('[Backup] full backup failed: $e');
      _snack('The full backup could not be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      dialogTitle: 'Choose a Front Porch backup',
      type: FileType.custom,
      allowedExtensions: const ['fpbackup'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final BackupManifest manifest;
    try {
      manifest = await PendingRestore.inspect(File(path));
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    final go = await showWarmDialog<bool>(
      context,
      title: 'Restore this backup?',
      icon: Icons.warning_amber_rounded,
      accent: AppColors.porchAmberOf(context),
      content: WarmDialogText(
        'Made ${formatRelativeTime(manifest.created)} by Front Porch AI '
        '${manifest.appVersion}, with ${manifest.fileCount} files. '
        '${manifest.hasSecrets ? 'It includes API keys and sign-ins.' : "It doesn't include API keys or sign-ins, so the ones on this computer stay."}'
        '\n\nYour library, settings and files are replaced the next time you '
        'open Front Porch AI. Anything changed after the backup was made is '
        'lost, but a snapshot of everything as it is now is taken first.',
      ),
      actions: [
        Builder(builder: (ctx) => warmDialogCancel(ctx, value: false)),
        Builder(
          builder: (ctx) => warmDialogConfirm(
            ctx,
            label: 'Restore',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ),
      ],
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await BackupService.stageFullRestore(File(path));
      widget.onChanged();
      if (mounted) await showRestartToFinish(context, manifest.created);
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      debugPrint('[Backup] staging the restore failed: $e');
      _snack('The restore could not be prepared: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.porchAmberOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'One file with your whole library, every setting (saved prompts, '
          'presets, themes, voices) and your own files: character pictures, '
          'galleries, worlds, backgrounds, imported voices and stories. '
          'Downloaded models and engines are left out; the app gets them '
          'again. Keep it on another drive, or use it to move to a new '
          'computer.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeSecrets,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _includeSecrets = v ?? false),
                  title: const Text('Include API keys and sign-ins'),
                  subtitle: const Text(
                    'Anyone with the file can use them. Leave this off for a '
                    'backup you share or store online.',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_alt_rounded, size: 18),
                      label: const Text('Save Full Backup…'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: AppColors.onAccentOf(context),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Restore From File…'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress, color: accent),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
