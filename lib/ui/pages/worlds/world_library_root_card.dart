// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wide header card for a root world that owns places (locations slice 3,
// mockup p1): name band with a "N places" chip that collapses the section,
// and the root's actions — "Add a place inside" first, because that is the
// verb the grouped library exists for.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/world_colors.dart';

class WorldLibraryRootCard extends StatelessWidget {
  const WorldLibraryRootCard({
    super.key,
    required this.section,
    required this.directCount,
    this.startingPlace,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onNewInside,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    this.selected,
    this.onSelected,
  });

  final WorldLibrarySection section;
  // Direct children for the chip — the mockup's Earth says "3 places"
  // while each continent's own chip counts deeper; the subtree is not
  // summed into the root's number.
  final int directCount;
  // Where chats attached to this world start (the starred place), or the
  // root itself when nothing is starred: then no line is shown.
  final World? startingPlace;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onNewInside;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  // Multi-select on the section header (same "Move into…" set as child
  // cards). The header tap stays collapse-toggle; long-press selects, the
  // badge tap steps out — mirroring WorldPlaceCard's pinned contract.
  final bool? selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final root = section.root;
    final accent = AppColors.formAccentOf(context);
    final worldColor = WorldColors.getColorForWorld(root.name);
    final entries = root.lorebook.entries.length;
    final total = directCount;
    final hasStart = startingPlace != null && startingPlace!.id != root.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: worldColor.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggleCollapsed,
              // Long-press joins "Move into…" selection like every other
              // card in the library (pinned contract: tap toggles the
              // section here, it always opened the editor nowhere else).
              onLongPress: onSelected == null ? null : () => onSelected!(true),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      worldColor.withValues(alpha: 0.30),
                      worldColor.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                ),
                child: Row(
                  children: [
                    if (selected == true) ...[
                      // Badge tap steps out of selection without touching
                      // collapse — the child cards' contract, same here.
                      GestureDetector(
                        key: Key('root-select-badge-${root.id}'),
                        onTap: () => onSelected?.call(false),
                        child: Icon(
                          Icons.check_circle,
                          size: 18,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Icon(
                      collapsed
                          ? Icons.folder_outlined
                          : Icons.folder_open_outlined,
                      size: 18,
                      color: worldColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        root.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    // "N places" chip doubles as the collapse toggle.
                    TextButton.icon(
                      key: Key('places-chip-${root.id}'),
                      onPressed: onToggleCollapsed,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: accent,
                      ),
                      icon: AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Icon(Icons.expand_more, size: 16),
                      ),
                      label: Text(
                        '$total place${total == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    root.description.isEmpty
                        ? 'No description'
                        : root.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: root.description.isEmpty
                          ? AppColors.textTertiary(context)
                          : AppColors.textSecondary(context),
                    ),
                  ),
                  // Every world with places has a starting place; an older
                  // world (or one whose starred place was deleted) is asked
                  // for one rather than silently starting at the world.
                  const SizedBox(height: 6),
                  Row(
                    key: Key('starting-place-${root.id}'),
                    children: [
                      Icon(
                        hasStart
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 14,
                        color: hasStart ? accent : AppColors.logError,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          hasStart
                              ? 'Chats start at ${startingPlace!.name}'
                              : 'Star a place below: chats start there',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: hasStart
                                ? AppColors.textSecondary(context)
                                : AppColors.logError,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        key: const Key('place-add-inside'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: accent,
                        ),
                        icon: const Icon(
                          Icons.add_location_alt_outlined,
                          size: 15,
                        ),
                        label: const Text(
                          'Add a place inside',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        onPressed: onNewInside,
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onEdit,
                        child: Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onExport,
                        child: Text(
                          'Export',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // A custom-biome root (biomeJson set, no built-in
                      // id) must not read as a bland "temperate".
                      Flexible(
                        child: Text(
                          root.climateEnabled
                              ? '${root.biomeId != null && root.biomeId!.isNotEmpty ? Biome.builtInById(root.biomeId)?.displayName ?? root.biomeId : (root.biomeJson != null ? 'Custom climate' : 'temperate')} · $entries ${entries == 1 ? 'entry' : 'entries'}'
                              : 'Weather off for the whole world · $entries '
                                    '${entries == 1 ? 'entry' : 'entries'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        icon: Icon(
                          Icons.delete_outline,
                          color: AppColors.logError,
                        ),
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
