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

import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The PNG cards and .byaf archives found under a picked folder.
typedef LibraryFolderFiles = ({List<File> pngs, List<File> byafs});

// The library window takes dropped PNG cards and .byaf files (not JSON).
const _cardsTip =
    'You can also drag PNG cards straight onto the library window.';
const _byafTip =
    'You can also drag .byaf files straight onto the library window.';

/// The pick step behind the library's Import Cards button. Null means there
/// is nothing to import: the user cancelled, or a failure was explained.
Future<List<File>?> pickLibraryCards(BuildContext context) async {
  final result = await GuardedPicker.pickFiles(
    context,
    category: PickerPrefs.catImport,
    type: FileType.custom,
    allowedExtensions: const ['png', 'json'],
    allowMultiple: true,
    tip: _cardsTip,
  );
  final paths = await _localPaths(result);
  return paths?.map(File.new).toList();
}

/// The pick step behind Import Backyard AI (.byaf).
Future<List<String>?> pickLibraryByafFiles(BuildContext context) async {
  final result = await GuardedPicker.pickFiles(
    context,
    category: PickerPrefs.catImport,
    type: FileType.custom,
    allowedExtensions: const ['byaf'],
    allowMultiple: true,
    tip: _byafTip,
  );
  return _localPaths(result);
}

Future<List<String>?> _localPaths(FilePickerResult? result) async {
  if (result == null || result.files.isEmpty) return null;
  final paths = <String>[];
  for (final f in result.files) {
    final path = await PickerPrefs.localPathOrTemp(f);
    if (path != null) paths.add(path);
  }
  return paths.isEmpty ? null : paths;
}

/// The pick step behind Import Folder: choose a folder, then list the cards
/// and archives under it. A folder that cannot be read is explained, with a
/// button to pick another.
Future<LibraryFolderFiles?> pickLibraryFolder(BuildContext context) async {
  while (true) {
    final dirPath = await GuardedPicker.getDirectoryPath(
      context,
      category: PickerPrefs.catDirectory,
      dialogTitle: 'Select folder containing character files',
      tip: _cardsTip,
    );
    if (dirPath == null) return null;
    try {
      return await scanLibraryFolder(dirPath);
    } catch (e, st) {
      debugPrint('[import] could not read folder "$dirPath": $e\n$st');
      if (!context.mounted) return null;
      final again = await showPickerFailure(
        context,
        kind: PickerFailureKind.readFolder,
        error: e,
        tip: _cardsTip,
      );
      if (!again || !context.mounted) return null;
    }
  }
}

/// Every .png and .byaf under [dirPath], subfolders included.
Future<LibraryFolderFiles> scanLibraryFolder(String dirPath) async {
  final pngs = <File>[];
  final byafs = <File>[];
  await for (final entity in Directory(dirPath).list(recursive: true)) {
    if (entity is! File) continue;
    final lower = entity.path.toLowerCase();
    if (lower.endsWith('.png')) {
      pngs.add(entity);
    } else if (lower.endsWith('.byaf')) {
      byafs.add(entity);
    }
  }
  return (pngs: pngs, byafs: byafs);
}
