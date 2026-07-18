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
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show SearchScope;

/// The home grid's search field, with a folder-scope selector prefix when a
/// folder is open. Extracted verbatim from CharacterCardGrid.build
/// (behavior-preserving).
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

  @override
  Widget build(BuildContext context) {
    return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                controller: searchController,
                style: TextStyle(color: AppColors.textPrimary(context)),
                decoration: InputDecoration(
                  hintText:
                      activeFolderId != null &&
                          searchScope != SearchScope.allCharacters
                      ? 'Search this folder...'
                      : 'Search by name or tag...',
                  hintStyle: TextStyle(color: AppColors.textTertiary(context)),
                  prefixIcon: activeFolderId != null
                      ? PopupMenuButton<SearchScope>(
                          icon: Icon(
                            searchScope == SearchScope.allCharacters
                                ? Icons.search
                                : Icons.folder_open,
                            color: searchScope == SearchScope.allCharacters
                                ? AppColors.porchHoneyOf(context)
                                : AppColors.porchAmberOf(context),
                            size: 20,
                          ),
                          tooltip: 'Search scope',
                          color: AppColors.surfaceContainerOf(context),
                          onSelected: onSearchScopeChanged,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: SearchScope.currentFolder,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder,
                                    size: 18,
                                    color:
                                        searchScope == SearchScope.currentFolder
                                        ? AppColors.porchAmberOf(context)
                                        : AppColors.iconSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'This Folder Only',
                                    style: TextStyle(
                                      color:
                                          searchScope ==
                                              SearchScope.currentFolder
                                          ? AppColors.porchAmberOf(context)
                                          : AppColors.textSecondary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SearchScope.folderRecursive,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.snippet_folder,
                                    size: 18,
                                    color:
                                        searchScope ==
                                            SearchScope.folderRecursive
                                        ? AppColors.porchAmberOf(context)
                                        : AppColors.iconSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Folder & Subfolders',
                                    style: TextStyle(
                                      color:
                                          searchScope ==
                                              SearchScope.folderRecursive
                                          ? AppColors.porchAmberOf(context)
                                          : AppColors.textSecondary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: SearchScope.allCharacters,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    size: 18,
                                    color:
                                        searchScope == SearchScope.allCharacters
                                        ? AppColors.porchHoneyOf(context)
                                        : AppColors.iconSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'All Characters',
                                    style: TextStyle(
                                      color:
                                          searchScope ==
                                              SearchScope.allCharacters
                                          ? AppColors.porchHoneyOf(context)
                                          : AppColors.textSecondary(context),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Icon(
                          Icons.search,
                          color: AppColors.iconSecondary(context),
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
