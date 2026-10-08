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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// What went wrong with a file window. Picks the dialog's words.
enum PickerFailureKind {
  open(
    title: "The file window didn't open",
    body:
        'Front Porch AI asked your computer for the window where you choose '
        "a file, but it didn't appear. Nothing was changed.\n\n"
        "Press Try again. If it still doesn't appear, close Front Porch AI "
        'and open it again.',
    retryLabel: 'Try again',
    icon: Icons.insert_drive_file_outlined,
  ),
  folder(
    title: "The folder window didn't open",
    body:
        'Front Porch AI asked your computer for the window where you choose '
        "a folder, but it didn't appear. Nothing was changed.\n\n"
        "Press Try again. If it still doesn't appear, close Front Porch AI "
        'and open it again.',
    retryLabel: 'Try again',
    icon: Icons.folder_off_outlined,
  ),
  save(
    title: "The file wasn't saved",
    body:
        'Something got in the way while saving the file.\n\n'
        'Press Try again and choose a different place to save it, such as '
        'your Documents folder.',
    retryLabel: 'Try again',
    icon: Icons.save_outlined,
  ),
  readFolder(
    title: "Couldn't look inside that folder",
    body:
        "Front Porch AI couldn't read the folder you picked. It may have been "
        'moved or renamed, or your computer may not let the app open it. '
        'Nothing was imported.',
    retryLabel: 'Pick another folder',
    icon: Icons.folder_off_outlined,
  );

  const PickerFailureKind({
    required this.title,
    required this.body,
    required this.retryLabel,
    required this.icon,
  });

  final String title;
  final String body;
  final String retryLabel;
  final IconData icon;
}

/// The plain-words dialog for a file window that failed. [tip] is a second
/// way to get the same thing done (dragging files onto the library).
/// Returns true when the user asks to try again.
Future<bool> showPickerFailure(
  BuildContext context, {
  required PickerFailureKind kind,
  required Object error,
  String? tip,
}) async {
  final again = await showWarmDialog<bool>(
    context,
    title: kind.title,
    icon: kind.icon,
    accent: AppColors.porchAmberOf(context),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WarmDialogText(kind.body),
        if (tip != null) ...[const SizedBox(height: 12), WarmDialogText(tip)],
        const SizedBox(height: 12),
        SelectableText(
          'Details for a bug report: $error',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    ),
    // Pop from inside the dialog so the right route closes.
    actions: [
      Builder(
        builder: (ctx) => warmDialogCancel(ctx, label: 'Close', value: false),
      ),
      Builder(
        builder: (ctx) => warmDialogConfirm(
          ctx,
          label: kind.retryLabel,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );
  return again == true;
}

/// [PickerPrefs] for screens: the same windows and remembered folders, but
/// a failure is logged, explained with [showPickerFailure] and returned as
/// null, the same as a cancel. Buttons start pickers without awaiting them,
/// so an error thrown from here would vanish and the click would do nothing.
class GuardedPicker {
  GuardedPicker._();

  static Future<FilePickerResult?> pickFiles(
    BuildContext context, {
    required String category,
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool lockParentWindow = false,
    String? tip,
  }) => _guard(
    context,
    PickerFailureKind.open,
    tip,
    () => PickerPrefs.pickFiles(
      category: category,
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      lockParentWindow: lockParentWindow,
    ),
  );

  static Future<String?> getDirectoryPath(
    BuildContext context, {
    required String category,
    String? dialogTitle,
    bool lockParentWindow = false,
    String? tip,
  }) => _guard(
    context,
    PickerFailureKind.folder,
    tip,
    () => PickerPrefs.getDirectoryPath(
      category: category,
      dialogTitle: dialogTitle,
      lockParentWindow: lockParentWindow,
    ),
  );

  static Future<String?> saveFile(
    BuildContext context, {
    required String category,
    required Uint8List bytes,
    String? dialogTitle,
    String? fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
    String? tip,
  }) => _guard(
    context,
    PickerFailureKind.save,
    tip,
    () => PickerPrefs.saveFile(
      category: category,
      bytes: bytes,
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      lockParentWindow: lockParentWindow,
    ),
  );

  static Future<String?> saveFromBuilder(
    BuildContext context, {
    required String category,
    required Future<void> Function(String tempPath) writeTemp,
    String? dialogTitle,
    required String fileName,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
    String? tip,
  }) => _guard(
    context,
    PickerFailureKind.save,
    tip,
    () => PickerPrefs.saveFromBuilder(
      category: category,
      writeTemp: writeTemp,
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      lockParentWindow: lockParentWindow,
    ),
  );

  static Future<T?> _guard<T>(
    BuildContext context,
    PickerFailureKind kind,
    String? tip,
    Future<T?> Function() open,
  ) async {
    while (true) {
      try {
        return await open();
      } catch (e, st) {
        debugPrint('[picker] ${kind.name} failed: $e\n$st');
        if (!context.mounted) return null;
        final again = await showPickerFailure(
          context,
          kind: kind,
          error: e,
          tip: tip,
        );
        if (!again || !context.mounted) return null;
      }
    }
  }
}
