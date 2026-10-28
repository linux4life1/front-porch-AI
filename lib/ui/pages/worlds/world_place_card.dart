// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Polished place card for Worlds management (Living Worlds).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_place_tags.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_starting_place.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// One place in the Worlds grid — cover (or letter), climate chip, actions.
class WorldPlaceCard extends StatelessWidget {
  final World world;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  /// Porch Stories: open New Story set in this world
  /// (docs/design/stories-in-worlds.md §3.4). No menu item without it.
  final VoidCallback? onWriteStory;
  // Locations slice 3. When set, a "placeCount places inside" chip and an
  // "Add a place inside" action render (root cards with children).
  final int placeCount;
  final VoidCallback? onNewInside;
  // Present when this world is a location: drives the "Inherits weather"
  // / "Owns its weather" tag the author needs to tell cards apart.
  final World? parent;
  // Multi-select ("Move into…"): the checkbox only renders when onSelected
  // is set, so untouched call sites keep today's exact card.
  final bool? selected;
  // False when the chain has no climate author — none owns one, or the
  // top-level world has weather off: the honest tag is "Weather off" (or
  // "Own climate · paused"), not a promise of something to inherit.
  // Defaults true so callers without chain access keep today's card.
  final bool hasWeatherToInherit;
  // Parent NAME for the "inside X" tag. Separate from [parent] because
  // the mockup marks depth only where it is not already obvious: section
  // children sit under their parent already (no tag), while flat/model-made
  // cards float free and need one.
  final String? insideName;
  final ValueChanged<bool>? onSelected;
  // The starting-place star (places inside a world only): filled when
  // chats attached to the world start here. No star without [onStar].
  final bool starred;
  final VoidCallback? onStar;
  // A world with places shows its "N places" toggle in the slot "Add a
  // place inside" takes on an empty world; [open] marks the card whose
  // places panel is showing.
  final Widget? placesToggle;
  final bool open;

  const WorldPlaceCard({
    super.key,
    required this.world,
    required this.onEdit,
    required this.onExport,
    this.onWriteStory,
    required this.onDelete,
    this.placeCount = 0,
    this.onNewInside,
    this.parent,
    this.insideName,
    this.selected,
    this.hasWeatherToInherit = true,
    this.onSelected,
    this.starred = false,
    this.onStar,
    this.placesToggle,
    this.open = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final worldColor = WorldColors.getColorForWorld(world.name);
    final climate = world.biomeId;
    final climateLabel =
        (world.climateEnabled &&
            hasWeatherToInherit &&
            climate != null &&
            climate.isNotEmpty &&
            climate != 'temperate')
        ? climate
        : null;
    // Inherit/own tag: only locations get one — a root's climate story is
    // its own chip above.
    final weatherTag = placeWeatherTag(
      world,
      isPlace: parent != null,
      hasWeatherToInherit: hasWeatherToInherit,
    );

    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.cardOf(context),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: open
              ? accent
              : AppColors.borderOf(context).withValues(alpha: 0.85),
        ),
      ),
      child: InkWell(
        // Tap always opens the editor (pinned by world_blank_name_test);
        // long-press enters "Move into…" selection, and the badge's own
        // tap steps out of it.
        onTap: onEdit,
        onLongPress: () => onSelected?.call(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverBackground(world: world, fallback: worldColor),
                  Positioned(
                    left: 12,
                    bottom: 10,
                    right: 48,
                    child: Text(
                      world.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        // Text sits on the cover photo, so it is the same in
                        // every theme.
                        color: InkColors.onImage,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: selected == true
                        ? GestureDetector(
                            onTap: () => onSelected?.call(false),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: InkColors.dim(0.35),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_circle,
                                size: 20,
                                color: accent,
                              ),
                            ),
                          )
                        : onStar != null
                        ? PlaceStarButton(
                            key: Key('place-star-${world.id}'),
                            starred: starred,
                            onTap: onStar!,
                          )
                        : const SizedBox.shrink(),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: InkColors.onImage.withValues(alpha: 0.95),
                      ),
                      color: AppColors.surfaceContainerOf(context),
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            onEdit();
                          case 'story':
                            onWriteStory?.call();
                          case 'export':
                            onExport();
                          case 'delete':
                            onDelete();
                          default:
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(
                            'Edit',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                        if (onWriteStory != null)
                          PopupMenuItem(
                            value: 'story',
                            key: Key('world-write-story-${world.id}'),
                            child: Text(
                              'Write a story here',
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text(
                            'Export .fpworld',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: AppColors.logError),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      world.description.isEmpty
                          ? 'No description'
                          : world.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: world.description.isEmpty
                            ? AppColors.textTertiary(context)
                            : AppColors.textSecondary(context),
                      ),
                    ),
                    const Spacer(),
                    if (placesToggle != null) ...[
                      placesToggle!,
                      const SizedBox(height: 6),
                    ] else if (onNewInside != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('place-add-inside'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
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
                      ),
                      const SizedBox(height: 2),
                    ],
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (climateLabel != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              climateLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                        if (weatherTag != null)
                          _tag(
                            context,
                            weatherTag,
                            muted:
                                !world.climateEnabled || !hasWeatherToInherit,
                          ),
                        if (insideName != null)
                          _tag(context, 'inside $insideName', muted: true),
                        if (world.isModelMade) _tag(context, 'model-made'),
                        if (world.sourceCharacterName != null)
                          _tag(context, 'from ${world.sourceCharacterName}'),
                        if (placeCount > 0 && placesToggle == null)
                          _tag(
                            context,
                            '$placeCount place${placeCount == 1 ? '' : 's'} inside',
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${world.lorebook.entries.length} '
                            '${world.lorebook.entries.length == 1 ? 'entry' : 'entries'}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label, {bool muted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.surfaceContainerOf(context)
            : AppColors.formAccentOf(context).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: muted
              ? AppColors.borderOf(context).withValues(alpha: 0.5)
              : AppColors.formAccentOf(context).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: muted
              ? AppColors.textTertiary(context)
              : AppColors.formAccentOf(context),
        ),
      ),
    );
  }
}

class _CoverBackground extends StatefulWidget {
  final World world;
  final Color fallback;

  const _CoverBackground({required this.world, required this.fallback});

  @override
  State<_CoverBackground> createState() => _CoverBackgroundState();
}

class _CoverBackgroundState extends State<_CoverBackground> {
  // base64-decoding the cover data-URL per build allocated a NEW byte list
  // every rebuild, which also defeated MemoryImage's identity-based cache —
  // so the grid re-decoded the full PNG on every rebuild and scroll recycle.
  // Memoize on the source string (same pattern as stoop_world_share).
  String? _coverSource;
  Uint8List? _coverBytes;

  World get world => widget.world;
  Color get fallback => widget.fallback;

  @override
  Widget build(BuildContext context) {
    if (!identical(world.coverImage, _coverSource)) {
      _coverSource = world.coverImage;
      _coverBytes = decodeWorldCoverBytes(world.coverImage);
    }
    final bytes = _coverBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // Grid-tile ground — decode small, not at source resolution.
        cacheWidth: 512,
        errorBuilder: (_, _, _) => _gradientFallback(),
      );
    }
    final path = world.avatarPath;
    if (path != null && path.isNotEmpty) {
      // No existsSync in build — Image.file errorBuilder handles missing files.
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _gradientFallback(),
      );
    }
    return _gradientFallback();
  }

  Widget _gradientFallback() {
    final initial = world.name.trim().isEmpty
        ? '?'
        : world.name.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            fallback.withValues(alpha: 0.85),
            AppColors.formAccentOf(context).withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: InkColors.onImage.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
