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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/library_import_picks.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Reports one finished item to a bulk import's progress dialog.
typedef HomeImportProgress =
    void Function(int current, int total, String name, String? error);

/// Runs one bulk import, reporting per item and honoring a cancel flag.
typedef HomeBulkImportRun =
    Future<void> Function({
      required HomeImportProgress onProgress,
      required bool Function() isCancelled,
    });

/// Folder import, multi-PNG import and the shared bulk-progress dialog,
/// all driven from [context] (the library view that started the import).
class HomeBulkImport {
  const HomeBulkImport(this.context);

  final BuildContext context;

  /// Several PNG/JSON cards under one progress dialog.
  Future<void> importCards(List<File> files) => _runBulkImport(files);

  /// PNG cards then BYAF archives under one progress dialog.
  Future<void> importBatch({
    required String title,
    required List<File> pngs,
    required List<String> byafs,
  }) => _importPngAndByafBatch(title: title, pngs: pngs, byafs: byafs);

  /// Any per-item import under the bulk-progress dialog.
  Future<void> runWithProgress({
    required String title,
    required int totalCount,
    required HomeBulkImportRun runImport,
  }) => _runBulkProgressImport(
    title: title,
    totalCount: totalCount,
    runImport: runImport,
  );

  Future<void> importFolder() async {
    // V2 PNG cards and Backyard AI (.byaf) files under the picked folder.
    final found = await pickLibraryFolder(context);
    if (found == null || !context.mounted) return;
    final (pngs: pngFiles, byafs: byafFiles) = found;

    if (pngFiles.isEmpty && byafFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No character cards (.png) or Backyard AI files (.byaf) found in '
            'the selected folder.',
          ),
        ),
      );
      return;
    }

    // Breakdown + per-type confirm: a mixed folder never imports anything
    // unexpectedly — the user sees exactly what's there and picks.
    final sel = await showHomeFolderImportDialog(context, pngFiles, byafFiles);
    if (sel == null || !context.mounted) return;
    final (importPng, importByaf, importChats, applySettings) = sel;

    final pngs = importPng ? pngFiles : <File>[];
    final byafs = importByaf
        ? byafFiles.map((f) => f.path).toList()
        : <String>[];
    if (pngs.isEmpty && byafs.isEmpty) return;

    await _importPngAndByafBatch(
      title: 'Import Folder',
      pngs: pngs,
      byafs: byafs,
      importChats: importChats,
      applySettings: applySettings,
    );
  }

  /// One progress dialog over PNG cards then BYAF archives. Folder import and
  /// a mixed desktop drop share this so the two kinds never stack dialogs.
  Future<void> _importPngAndByafBatch({
    required String title,
    required List<File> pngs,
    required List<String> byafs,
    bool importChats = true,
    bool applySettings = true,
  }) {
    final total = pngs.length + byafs.length;
    if (total == 0) return Future<void>.value();
    return _runBulkProgressImport(
      title: title,
      totalCount: total,
      runImport: ({required onProgress, required isCancelled}) async {
        var done = 0;
        if (pngs.isNotEmpty) {
          final repo = Provider.of<CharacterRepository>(context, listen: false);
          await repo.importCharacters(
            pngs,
            isCancelled: isCancelled,
            onProgress: (current, _, name, error) =>
                onProgress(done + current, total, name, error),
          );
          done += pngs.length;
        }
        if (byafs.isNotEmpty && !isCancelled()) {
          await importHomeByafFiles(
            context,
            byafs,
            importChats,
            applySettings: applySettings,
            onProgress: (current, _, name, error) =>
                onProgress(done + current, total, name, error),
            isCancelled: isCancelled,
          );
        }
      },
    );
  }

  /// Shared bulk PNG import with progress dialog — used by both multi-select
  /// and folder import.
  Future<void> _runBulkImport(List<File> files) {
    return _runBulkProgressImport(
      title: 'Bulk Import',
      totalCount: files.length,
      runImport: ({required onProgress, required isCancelled}) async {
        final repo = Provider.of<CharacterRepository>(context, listen: false);
        await repo.importCharacters(
          files,
          isCancelled: isCancelled,
          onProgress: onProgress,
        );
      },
    );
  }

  /// Generic bulk-import progress dialog. Drives any import that reports
  /// (current, total, name, error) per item and honors a cancel flag — used by
  /// both the V2 PNG bulk import and the BYAF (Backyard AI) bulk import.
  ///
  /// The returned Future completes when [runImport] finishes (file IO done),
  /// not when the dialog is merely shown. Desktop drop holds macOS bookmarks
  /// and HomeDropZone._busy on that Future.
  Future<void> _runBulkProgressImport({
    required String title,
    required int totalCount,
    required HomeBulkImportRun runImport,
  }) {
    if (!context.mounted || totalCount == 0) return Future<void>.value();
    final finished = Completer<void>();
    bool cancelled = false;
    bool started = false;
    int currentCount = 0;
    int importedCount = 0;
    int failedCount = 0;
    String currentName = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Start the import after the first build, never inside it: an
            // import notifies the repository before its first await, and a
            // notify during build throws.
            if (!started) {
              started = true;
              Future.microtask(
                    () => runImport(
                      isCancelled: () => cancelled,
                      onProgress: (current, total, name, error) {
                        if (ctx.mounted) {
                          setDialogState(() {
                            currentCount = current;
                            currentName = name;
                            if (error == null) {
                              importedCount++;
                            } else {
                              failedCount++;
                            }
                          });
                        }
                      },
                    ),
                  )
                  .then((_) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      final msg = failedCount > 0
                          ? 'Imported $importedCount character${importedCount == 1 ? '' : 's'} ($failedCount failed)'
                          : 'Imported $importedCount character${importedCount == 1 ? '' : 's'} successfully!';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(msg)));
                    }
                  })
                  .catchError((Object e) {
                    debugPrint('[BulkImport] $e');
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  })
                  .whenComplete(() {
                    if (!finished.isCompleted) finished.complete();
                  });
            }

            final progress = totalCount > 0 ? currentCount / totalCount : 0.0;

            return AlertDialog(
              backgroundColor: AppColors.surfaceOf(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: AppColors.porchHoneyOf(ctx).withValues(alpha: 0.5),
                ),
              ),
              title: Row(
                children: [
                  Icon(Icons.library_add, color: AppColors.porchHoneyOf(ctx)),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(ctx),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: AppColors.surfaceContainerOf(ctx),
                        valueColor: AlwaysStoppedAnimation(
                          AppColors.porchHoneyOf(ctx),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Status text
                    Text(
                      currentCount == 0
                          ? 'Starting import...'
                          : 'Importing $currentCount of $totalCount...',
                      style: TextStyle(
                        color: AppColors.textSecondary(ctx),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Current file name
                    if (currentName.isNotEmpty)
                      Text(
                        currentName,
                        style: TextStyle(
                          color: AppColors.textTertiary(ctx),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 16),
                    // Counts row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _bulkStatChip(
                          Icons.check_circle,
                          AppColors.verifiedAccentOf(ctx),
                          '$importedCount imported',
                        ),
                        const SizedBox(width: 16),
                        _bulkStatChip(
                          Icons.error,
                          AppColors.negativeAccentOf(ctx),
                          '$failedCount failed',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                  },
                  child: Text(
                    cancelled ? 'Cancelling...' : 'Cancel',
                    style: TextStyle(
                      color: cancelled
                          ? AppColors.textTertiary(ctx)
                          : AppColors.negativeAccentOf(ctx),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return finished.future;
  }

  Widget _bulkStatChip(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}
