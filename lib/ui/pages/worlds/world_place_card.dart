// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Polished place card for Worlds management (Living Worlds).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// One place in the Worlds grid — cover (or letter), climate chip, actions.
class WorldPlaceCard extends StatelessWidget {
  final World world;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const WorldPlaceCard({
    super.key,
    required this.world,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final worldColor = WorldColors.getColorForWorld(world.name);
    final climate = world.biomeId;
    final climateLabel =
        (climate != null && climate.isNotEmpty && climate != 'temperate')
        ? climate
        : null;

    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.cardOf(context),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.borderOf(context).withValues(alpha: 0.85),
        ),
      ),
      child: InkWell(
        onTap: onEdit,
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
                        // Deliberately raw white/black: text sits ON the cover
                        // photo, so contrast must be theme-independent (not an
                        // AppColors chrome accent).
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                      color: AppColors.surfaceContainerOf(context),
                      onSelected: (action) {
                        switch (action) {
                          case 'edit':
                            onEdit();
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
                    Row(
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
                          const SizedBox(width: 6),
                        ],
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
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
