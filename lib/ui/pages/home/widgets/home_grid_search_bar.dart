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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/library_view.dart' show SearchScope;

/// The home grid's search field. Its leading button picks where a search
/// looks, at every level (#346): inside a folder This Folder Only, Folder &
/// Subfolders or All Characters; at the top level Everywhere or Top level
/// only (cards in no folder).
class HomeGridSearchBar extends StatelessWidget {
  const HomeGridSearchBar({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.searchScope,
    required this.activeFolderId,
    required this.onSearchScopeChanged,
    required this.onSearchQueryChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final SearchScope searchScope;
  final String? activeFolderId;
  final void Function(SearchScope scope) onSearchScopeChanged;
  final void Function(String query) onSearchQueryChanged;

  /// At the top level, Folder & Subfolders is the whole library.
  bool get _everywhere =>
      searchScope == SearchScope.allCharacters ||
      (activeFolderId == null && searchScope == SearchScope.folderRecursive);

  PopupMenuItem<SearchScope> _scopeItem(
    BuildContext context,
    SearchScope value,
    IconData icon,
    String label, {
    required bool selected,
    required Color accent,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? accent : AppColors.iconSecondary(context),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: selected ? accent : AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<SearchScope>> _scopeItems(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    final amber = AppColors.porchAmberOf(context);
    if (activeFolderId == null) {
      return [
        _scopeItem(
          context,
          SearchScope.allCharacters,
          Icons.search,
          'Everywhere',
          selected: _everywhere,
          accent: honey,
        ),
        _scopeItem(
          context,
          SearchScope.currentFolder,
          Icons.folder,
          'Top level only',
          selected: !_everywhere,
          accent: amber,
        ),
      ];
    }
    return [
      _scopeItem(
        context,
        SearchScope.currentFolder,
        Icons.folder,
        'This Folder Only',
        selected: searchScope == SearchScope.currentFolder,
        accent: amber,
      ),
      _scopeItem(
        context,
        SearchScope.folderRecursive,
        Icons.snippet_folder,
        'Folder & Subfolders',
        selected: searchScope == SearchScope.folderRecursive,
        accent: amber,
      ),
      _scopeItem(
        context,
        SearchScope.allCharacters,
        Icons.search,
        'All Characters',
        selected: searchScope == SearchScope.allCharacters,
        accent: honey,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: TextField(
        controller: searchController,
        style: TextStyle(color: AppColors.textPrimary(context)),
        decoration: InputDecoration(
          hintText: activeFolderId != null && !_everywhere
              ? 'Search this folder...'
              : 'Search by name or tag...',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          prefixIcon: PopupMenuButton<SearchScope>(
            icon: Icon(
              _everywhere ? Icons.search : Icons.folder_open,
              color: _everywhere
                  ? AppColors.porchHoneyOf(context)
                  : AppColors.porchAmberOf(context),
              size: 20,
            ),
            tooltip: 'Search scope',
            color: AppColors.surfaceContainerOf(context),
            onSelected: onSearchScopeChanged,
            itemBuilder: _scopeItems,
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () {
                    searchController.clear();
                    onSearchQueryChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: onSearchQueryChanged,
      ),
    );
  }
}
