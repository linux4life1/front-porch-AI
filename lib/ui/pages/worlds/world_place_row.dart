// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One place inside a world, as a row in that world's places panel. Places
// get rows, never cards: a library of many worlds stays a grid of worlds.
// Tap opens the editor, long-press joins the "Move into…" selection (the
// card contract), and the menu holds Edit, Move to… and Delete. There is
// no Export: a place leaves the app only inside its whole world.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_place_tags.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Below this width the description drops under the name.
const double _kStackBelow = 560;

class WorldPlaceRow extends StatelessWidget {
  const WorldPlaceRow({
    super.key,
    required this.place,
    required this.depth,
    required this.hasWeatherToInherit,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
    this.insideName,
    this.starred = false,
    this.onStar,
    this.onNewInside,
    this.selected,
    this.onSelected,
  });

  final World place;

  /// 1 for a place in the world, 2 for a room in a building.
  final int depth;
  final bool hasWeatherToInherit;
  final VoidCallback onEdit;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  /// Shown as an "inside X" tag where the tree is not on screen (the
  /// model-made list).
  final String? insideName;
  final bool starred;
  final VoidCallback? onStar;

  /// Null at the depth cap: a room takes no places inside it.
  final VoidCallback? onNewInside;
  final bool? selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final weather = placeWeatherTag(
      place,
      isPlace: true,
      hasWeatherToInherit: hasWeatherToInherit,
    );
    final tags = <Widget>[
      if (weather != null)
        _tag(
          context,
          weather,
          active: place.climateEnabled && hasWeatherToInherit,
        ),
      if (insideName != null) _tag(context, 'inside $insideName'),
      if (place.isModelMade) _tag(context, 'model-made', active: true),
      _tag(context, entriesLabel(place)),
    ];
    final name = Text(
      place.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary(context),
      ),
    );
    final description = Text(
      place.description.isEmpty ? 'No description' : place.description,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        color: place.description.isEmpty
            ? AppColors.textTertiary(context)
            : AppColors.textSecondary(context),
      ),
    );

    return InkWell(
      key: Key('place-row-${place.id}'),
      onTap: onEdit,
      onLongPress: onSelected == null ? null : () => onSelected!(true),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.only(left: (depth - 1) * 28.0, right: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < _kStackBelow;
              return Row(
                children: [
                  if (depth > 1)
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: AppColors.textTertiary(context),
                    ),
                  _lead(context, accent),
                  const SizedBox(width: 6),
                  if (narrow)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            name,
                            const SizedBox(height: 2),
                            description,
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 4, children: tags),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    SizedBox(width: 190, child: name),
                    const SizedBox(width: 12),
                    Expanded(child: description),
                    const SizedBox(width: 12),
                    Wrap(spacing: 6, runSpacing: 4, children: tags),
                  ],
                  _addInside(context, accent),
                  _menu(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The star, or the selection badge while the row is selected.
  Widget _lead(BuildContext context, Color accent) {
    if (selected == true) {
      return IconButton(
        tooltip: 'Deselect',
        onPressed: () => onSelected?.call(false),
        icon: Icon(Icons.check_circle, size: 20, color: accent),
      );
    }
    if (onStar == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.place_outlined,
          size: 18,
          color: AppColors.textTertiary(context),
        ),
      );
    }
    return IconButton(
      key: Key('place-star-${place.id}'),
      tooltip: starred
          ? 'Chats in this world start here'
          : 'Start chats in this world here',
      onPressed: onStar,
      icon: Icon(
        starred ? Icons.star_rounded : Icons.star_border_rounded,
        size: 20,
        color: starred ? accent : AppColors.textTertiary(context),
        semanticLabel: starred ? 'Starting place' : 'Set starting place',
      ),
    );
  }

  Widget _addInside(BuildContext context, Color accent) {
    if (onNewInside == null) return const SizedBox(width: 40);
    return IconButton(
      key: Key('place-add-inside-${place.id}'),
      tooltip: 'Add a place inside ${place.name}',
      onPressed: onNewInside,
      icon: Icon(Icons.add_location_alt_outlined, size: 18, color: accent),
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Place actions',
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: AppColors.textSecondary(context),
      ),
      color: AppColors.surfaceContainerOf(context),
      onSelected: (action) {
        switch (action) {
          case 'edit':
            onEdit();
          case 'move':
            onMove();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Text(
            'Edit',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
        ),
        PopupMenuItem(
          value: 'move',
          child: Text(
            'Move to…',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppColors.logError)),
        ),
      ],
    );
  }

  Widget _tag(BuildContext context, String label, {bool active = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active
            ? AppColors.formAccentOf(context).withValues(alpha: 0.10)
            : AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: active
              ? AppColors.formAccentOf(context)
              : AppColors.textTertiary(context),
        ),
      ),
    );
  }
}
