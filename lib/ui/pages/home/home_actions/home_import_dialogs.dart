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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

// Confirm dialogs in front of the bulk imports (folder and multi-BYAF).

/// Mass BYAF confirm: once for the whole batch, with a chat-history and a
/// model-settings choice. Returns null on cancel.
Future<({bool importChats, bool applySettings})?> showHomeBulkByafConfirm(
  BuildContext context,
  List<String> paths,
) async {
  bool importChats = true;
  bool applySettings = true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Import ${paths.length} Backyard AI characters?',
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
              'Each .byaf will be imported as a character card. (No per-file '
              'preview is shown for batch imports.)',
              style: TextStyle(
                color: AppColors.textSecondary(ctx),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: importChats,
              onChanged: (v) => setLocal(() => importChats = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Also import chat history',
                style: TextStyle(color: AppColors.textPrimary(ctx)),
              ),
            ),
            CheckboxListTile(
              value: applySettings,
              onChanged: (v) => setLocal(() => applySettings = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Apply Backyard model settings',
                style: TextStyle(color: AppColors.textPrimary(ctx)),
              ),
              subtitle: Text(
                "Each import uses its archive's sampler values "
                '(temperature, min-p, …) for the imported chat',
                style: TextStyle(
                  color: AppColors.textSecondary(ctx),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Import ${paths.length}'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return null;
  return (importChats: importChats, applySettings: applySettings);
}

/// Per-type confirm for folder import. Shows the breakdown (PNG vs BYAF) with
/// independent checkboxes so a mixed folder is a conscious choice, not a
/// surprise. Returns (importPng, importByaf, importChats, applySettings), or null on
/// cancel.
Future<(bool, bool, bool, bool)?> showHomeFolderImportDialog(
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
