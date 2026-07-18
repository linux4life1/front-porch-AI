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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;

/// The home grid's top toolbar: selection/organize header or folder breadcrumb
/// or the Characters/Stories mode toggle, plus the sort dropdown, grid-size
/// slider, and the refresh / multi-select / organize / new-folder / import
/// actions. Extracted verbatim from CharacterCardGrid.build (behavior-preserving).
class HomeGridToolbar extends StatelessWidget {
  const HomeGridToolbar({
    super.key,
    required this.isSelecting,
    required this.isOrganizing,
    required this.activeFolderId,
    required this.selectedCharacterIds,
    required this.sortMode,
    required this.gridScale,
    required this.modeToggle,
    required this.repo,
    required this.folderService,
    required this.onCancelSelection,
    required this.onFolderNavigateBack,
    required this.onSortChanged,
    required this.onGridScaleChanged,
    required this.onGridScaleChangeEnd,
    required this.onToggleSelectMode,
    required this.onToggleOrganizeMode,
    required this.onFolderDialogAction,
    required this.onImport,
  });

  final bool isSelecting;
  final bool isOrganizing;
  final String? activeFolderId;
  final Set<String> selectedCharacterIds;
  final String sortMode;
  final double gridScale;
  final Widget modeToggle;
  final CharacterRepository repo;
  final FolderService folderService;
  final VoidCallback onCancelSelection;
  final VoidCallback onFolderNavigateBack;
  final void Function(String mode) onSortChanged;
  final void Function(double scale) onGridScaleChanged;
  final void Function(double scale)? onGridScaleChangeEnd;
  final VoidCallback? onToggleSelectMode;
  final VoidCallback? onToggleOrganizeMode;
  final void Function(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  })
  onFolderDialogAction;
  final void Function(String source) onImport;

  String _getActiveFolderName() {
    if (activeFolderId == null) return 'My Characters';
    final folder = folderService.folders
        .where((f) => f.id == activeFolderId)
        .firstOrNull;
    return folder?.name ?? 'Folder';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Row(
                children: [
                  if (isSelecting || isOrganizing) ...[
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel selection',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCancelSelection,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${selectedCharacterIds.length} selected',
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isOrganizing
                                  ? AppColors.porchHoneyOf(context)
                                  : AppColors.porchTerracottaOf(context),
                            ),
                      ),
                    ),
                  ] else if (activeFolderId != null) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to all characters',
                      visualDensity: VisualDensity.compact,
                      onPressed: onFolderNavigateBack,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _getActiveFolderName(),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else
                    modeToggle,
                  const SizedBox(width: 12),
                  if (!isSelecting && !isOrganizing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: sortMode,
                          icon: Icon(
                            Icons.sort,
                            size: 18,
                            color: AppColors.iconSecondary(context),
                          ),
                          dropdownColor: AppColors.surfaceContainerOf(context),
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                          ),
                          isDense: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('Name (A\u2192Z)'),
                            ),
                            DropdownMenuItem(
                              value: 'recent',
                              child: Text('Recent Activity'),
                            ),
                            DropdownMenuItem(
                              value: 'importDate',
                              child: Text('Import Date'),
                            ),
                            DropdownMenuItem(
                              value: 'messages',
                              child: Text('Messages Sent'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) onSortChanged(value);
                          },
                        ),
                      ),
                    ),
                  if (!isSelecting && !isOrganizing)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 100,
                        child: Row(
                          children: [
                            Icon(
                              Icons.grid_view,
                              size: 16,
                              color: AppColors.iconSecondary(context),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: AppColors.porchHoneyOf(
                                    context,
                                  ).withValues(alpha: 0.7),
                                  inactiveTrackColor: AppColors.borderOf(
                                    context,
                                  ).withValues(alpha: 0.4),
                                  thumbColor: AppColors.porchHoneyOf(context),
                                ),
                                child: Slider(
                                  value: gridScale,
                                  min: 150,
                                  max: 450,
                                  onChanged: (v) => onGridScaleChanged(v),
                                  onChangeEnd: (v) =>
                                      onGridScaleChangeEnd?.call(v),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.view_module,
                              size: 16,
                              color: AppColors.iconSecondary(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (!isSelecting && !isOrganizing) ...[
                    // Full reload via loadCharacters() (DB re-query + fresh PNG extensions/avatars)
                    // so external direct writers (Character Card Forge, web imports, etc.) are
                    // picked up immediately without app restart. Matches the established pattern
                    // used by cloud sync, the web server, and main.dart startup.
                    IconButton(
                      tooltip:
                          'Refresh character list (pick up external changes, e.g. Character Card Forge)',
                      icon: const Icon(Icons.refresh),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => repo.loadCharacters(),
                    ),
                    IconButton(
                      tooltip:
                          'Multi-select characters (for organizing, moving, etc.)',
                      icon: const Icon(Icons.check_box_outlined),
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleSelectMode,
                    ),
                    IconButton(
                      tooltip: 'Organize into folders',
                      icon: Icon(
                        Icons.drive_file_move_outlined,
                        color: AppColors.porchHoneyOf(context),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleOrganizeMode,
                    ),
                    if (activeFolderId == null)
                      IconButton(
                        tooltip: 'New Folder',
                        icon: const Icon(Icons.create_new_folder_outlined),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            onFolderDialogAction(FolderDialogAction.create),
                      ),
                    if (activeFolderId != null)
                      IconButton(
                        tooltip: 'New Subfolder',
                        icon: Icon(
                          Icons.create_new_folder_outlined,
                          color: AppColors.porchAmberOf(context),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onFolderDialogAction(
                          FolderDialogAction.create,
                          parentId: activeFolderId,
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Import or discover characters',
                      icon: const Icon(Icons.download),
                      onSelected: onImport,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'cards',
                          child: ListTile(
                            leading: Icon(Icons.download),
                            title: Text('Import Cards'),
                            dense: true,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'folder',
                          child: ListTile(
                            leading: Icon(Icons.library_add),
                            title: Text('Import Folder'),
                            dense: true,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'byaf',
                          child: ListTile(
                            leading: Icon(Icons.archive_outlined),
                            title: Text('Import Backyard AI (.byaf)'),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
  }
}
