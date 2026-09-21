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

/// Desktop PNG/BYAF drop → the same import methods the picker uses.
extension _HomePageDrop on _HomePageState {
  Widget _wrapChatsWithDrop(BuildContext context, Widget child) {
    return HomeDropZone(
      onDrop: (sources) => _importDroppedFiles(context, sources),
      child: child,
    );
  }

  Future<void> _importDroppedFiles(
    BuildContext context,
    List<HomeDropSource> sources,
  ) async {
    final plan = planHomeDropSources(sources);
    if (!context.mounted) return;
    if (plan.rejectMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(plan.rejectMessage!)));
    }
    if (plan.isMixed) {
      await _importPngAndByafBatch(
        context,
        title: 'Import dropped files',
        pngs: [for (final path in plan.pngPaths) File(path)],
        byafs: plan.byafPaths,
      );
      return;
    }
    if (plan.pngPaths.isNotEmpty) {
      await _importCharacterFromFiles(context, [
        for (final path in plan.pngPaths) File(path),
      ]);
    }
    if (plan.byafPaths.isNotEmpty && context.mounted) {
      await _importByafFromPaths(context, plan.byafPaths);
    }
  }
}
