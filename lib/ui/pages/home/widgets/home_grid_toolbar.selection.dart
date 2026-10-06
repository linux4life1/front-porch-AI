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
// along with Front Porch AI. If not, see https://www.gnu.org/licenses/.

part of 'home_grid_toolbar.dart';

/// What the selection header's Select all / Select none do (#347). A null
/// callback greys its button out: nothing left to add, or nothing picked.
class LibrarySelectionActions {
  const LibrarySelectionActions({this.selectAll, this.selectNone});

  final VoidCallback? selectAll;
  final VoidCallback? selectNone;
}

/// The header while picking cards: close, "N selected" (with a smaller
/// "(M hidden)" when a search or folder change hides some picks), then
/// Select all and Select none.
extension _HomeGridToolbarSelection on HomeGridToolbar {
  List<Widget> _selectionChildren(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final actions = selectionActions;
    final accent = TextButton.styleFrom(
      foregroundColor: AppColors.porchAmberOf(context),
      visualDensity: VisualDensity.compact,
    );
    return [
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        visualDensity: VisualDensity.compact,
        onPressed: onCancelSelection,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text.rich(
          TextSpan(
            text: '$selectedCount selected',
            style: theme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isOrganizing
                  ? AppColors.porchHoneyOf(context)
                  : AppColors.porchTerracottaOf(context),
            ),
            children: [
              if (hiddenSelectedCount > 0)
                TextSpan(
                  text: ' ($hiddenSelectedCount hidden)',
                  style: theme.titleSmall?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
      if (actions != null) ...[
        const SizedBox(width: 12),
        TextButton(
          onPressed: actions.selectAll,
          style: accent,
          child: const Text('Select all'),
        ),
        TextButton(
          onPressed: actions.selectNone,
          style: accent,
          child: const Text('Select none'),
        ),
      ],
    ];
  }
}
