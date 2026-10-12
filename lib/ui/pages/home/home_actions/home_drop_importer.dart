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

import 'package:front_porch_ai/ui/pages/home/home_drop_import.dart';
import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';

/// Desktop PNG/BYAF/.porch drop → the same import methods the picker uses.
/// [context] is the library view the files were dropped on;
/// [importPorchPaths] is the Import menu's `.porch` importer.
class HomeDropImport {
  const HomeDropImport(this.context, {required this.importPorchPaths});

  final BuildContext context;
  final Future<void> Function(List<String> paths) importPorchPaths;

  Future<void> importDroppedFiles(List<HomeDropSource> sources) async {
    final plan = planHomeDropSources(sources);
    if (!context.mounted) return;
    if (plan.rejectMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(plan.rejectMessage!)));
    }
    if (plan.isMixed) {
      await HomeBulkImport(context).importBatch(
        title: 'Import dropped files',
        pngs: [for (final path in plan.pngPaths) File(path)],
        byafs: plan.byafPaths,
      );
    } else {
      if (plan.pngPaths.isNotEmpty) {
        await HomeCardImport(
          context,
        ).importFiles([for (final path in plan.pngPaths) File(path)]);
      }
      if (plan.byafPaths.isNotEmpty && context.mounted) {
        await HomeCardImport(context).importByafPaths(plan.byafPaths);
      }
    }
    if (plan.porchPaths.isNotEmpty && context.mounted) {
      await importPorchPaths(plan.porchPaths);
    }
  }
}
