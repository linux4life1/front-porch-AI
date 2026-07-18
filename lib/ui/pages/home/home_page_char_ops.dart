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

part of '../home_page.dart';

/// Character/BYAF import + bulk-import progress + folder import.
///
/// Split out of the _HomePageState god file as a private extension
/// (part of the same library, so it keeps full access to page state).
extension _HomePageCharOps on _HomePageState {
  Future<void> _folderImportCharacters(BuildContext context) async {
    final dirPath = await PickerPrefs.getDirectoryPath(
      category: PickerPrefs.catDirectory,
      dialogTitle: 'Select folder containing character files',
    );

    if (dirPath == null) return;
    if (!context.mounted) return;

    // Scan for both V2 PNG cards and Backyard AI (.byaf) files.
    final pngFiles = <File>[];
    final byafFiles = <File>[];
    await for (final entity in Directory(dirPath).list(recursive: true)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.png')) {
        pngFiles.add(entity);
      } else if (lower.endsWith('.byaf')) {
        byafFiles.add(entity);
      }
    }

    if (pngFiles.isEmpty && byafFiles.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No character cards (.png) or Backyard AI files (.byaf) found in '
              'the selected folder.',
            ),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;

    // Breakdown + per-type confirm: a mixed folder never imports anything
    // unexpectedly — the user sees exactly what's there and picks.
    final sel = await _confirmFolderImport(context, pngFiles, byafFiles);
    if (sel == null || !context.mounted) return;
    final (importPng, importByaf, importChats, applySettings) = sel;

    final pngs = importPng ? pngFiles : <File>[];
    final byafs = importByaf
        ? byafFiles.map((f) => f.path).toList()
        : <String>[];
    if (pngs.isEmpty && byafs.isEmpty) return;

    final total = pngs.length + byafs.length;
    _runBulkProgressImport(
      context,
      title: 'Import Folder',
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
          await _importByafFiles(
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

  /// Per-type confirm for folder import. Shows the breakdown (PNG vs BYAF) with
  /// independent checkboxes so a mixed folder is a conscious choice, not a
  /// surprise. Returns (importPng, importByaf, importChats), or null on cancel.
  Future<(bool, bool, bool, bool)?> _confirmFolderImport(
    BuildContext context,
    List<File> pngFiles,
    List<File> byafFiles,
  ) {
    bool importPng = pngFiles.isNotEmpty;
    bool importByaf = byafFiles.isNotEmpty;
    bool importChats = true;
    bool applySettings = true;
    final accent = AppColors.porchHoneyOf(context);
    return showDialog<(bool, bool, bool, bool)>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final count =
              (importPng ? pngFiles.length : 0) +
              (importByaf ? byafFiles.length : 0);
          return AlertDialog(
            backgroundColor: AppColors.surfaceOf(ctx),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
            ),
            title: Row(
              children: [
                Icon(Icons.library_add, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Import from folder',
                    style: TextStyle(color: AppColors.textPrimary(ctx)),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This folder contains:',
                  style: TextStyle(
                    color: AppColors.textSecondary(ctx),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                if (pngFiles.isNotEmpty)
                  CheckboxListTile(
                    value: importPng,
                    onChanged: (v) => setLocal(() => importPng = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      '${pngFiles.length} character card${pngFiles.length == 1 ? '' : 's'} (V2 PNG)',
                      style: TextStyle(color: AppColors.textPrimary(ctx)),
                    ),
                  ),
                if (byafFiles.isNotEmpty)
                  CheckboxListTile(
                    value: importByaf,
                    onChanged: (v) => setLocal(() => importByaf = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      '${byafFiles.length} Backyard AI file${byafFiles.length == 1 ? '' : 's'} (.byaf)',
                      style: TextStyle(color: AppColors.textPrimary(ctx)),
                    ),
                  ),
                if (byafFiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: CheckboxListTile(
                      value: importChats && importByaf,
                      onChanged: importByaf
                          ? (v) => setLocal(() => importChats = v ?? true)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'also import their chat history',
                        style: TextStyle(
                          color: importByaf
                              ? AppColors.textSecondary(ctx)
                              : AppColors.textTertiary(ctx),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                if (byafFiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: CheckboxListTile(
                      value: applySettings && importByaf,
                      onChanged: importByaf
                          ? (v) => setLocal(() => applySettings = v ?? true)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'apply their Backyard model settings',
                        style: TextStyle(
                          color: importByaf
                              ? AppColors.textSecondary(ctx)
                              : AppColors.textTertiary(ctx),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textTertiary(ctx)),
                ),
              ),
              ElevatedButton(
                onPressed: count == 0
                    ? null
                    : () => Navigator.pop(ctx, (
                        importPng,
                        importByaf,
                        importChats,
                        applySettings,
                      )),
                child: Text('Import $count'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shared bulk PNG import with progress dialog — used by both multi-select
  /// and folder import.
  void _runBulkImport(BuildContext context, List<File> files) {
    _runBulkProgressImport(
      context,
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
  void _runBulkProgressImport(
    BuildContext context, {
    required String title,
    required int totalCount,
    required Future<void> Function({
      required void Function(int current, int total, String name, String? error)
      onProgress,
      required bool Function() isCancelled,
    })
    runImport,
  }) {
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
            // Start the import on first build.
            if (!started) {
              started = true;
              runImport(
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
              ).then((_) {
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  final msg = failedCount > 0
                      ? 'Imported $importedCount character${importedCount == 1 ? '' : 's'} ($failedCount failed)'
                      : 'Imported $importedCount character${importedCount == 1 ? '' : 's'} successfully!';
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
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
