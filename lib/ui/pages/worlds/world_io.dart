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
//
// Desktop .fpworld file flows for the Worlds page: export a place package,
// and import one through WorldRepository.importWorld — the full-package
// path that keeps climate, place traits, and lore (the lorebook import
// page is for bare lore files and would drop all of that).

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Pick a `.fpworld` (or bare lorebook `.json`) and import it as a new
/// place, preserving climate + place traits + lore.
Future<void> importFpWorldFlow(
  BuildContext context,
  WorldRepository repo,
) async {
  final result = await PickerPrefs.pickFiles(
    category: PickerPrefs.catImport,
    dialogTitle: 'Import Place (.fpworld)',
    type: FileType.custom,
    allowedExtensions: ['fpworld', 'json'],
  );
  final path = result?.files.firstOrNull?.path;
  if (path == null) return;
  try {
    final world = await repo.importWorld(File(path));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported "${world.name}"')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

/// Save [world] as a portable `.fpworld` place package (lore + climate +
/// traits).
Future<void> exportFpWorldFlow(
  BuildContext context,
  WorldRepository repo,
  World world,
) async {
  String? outputFile = await PickerPrefs.saveFromBuilder(
    category: PickerPrefs.catExport,
    dialogTitle: 'Export World (.fpworld)',
    fileName: '${world.name}.fpworld',
    type: FileType.custom,
    allowedExtensions: ['fpworld', 'json'],
    writeTemp: (path) => repo.exportFpWorld(world, path),
  );
  if (outputFile == null) return;
  try {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported place package to $outputFile')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}
