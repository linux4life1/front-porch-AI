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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A single tile in the unified Avatar Gallery — used for the portrait, gallery
/// avatars, and expression images alike. Pure presentation: every action is a
/// callback the parent (controller) owns.
///
/// Three independent hit targets: the body ([onTap] — "use this look" in a chat,
/// or "set default emotion" for an expression), the ★ ([onStar] — set as the one
/// canonical avatar), and the ✕ ([onDelete] — omitted for the portrait). An
/// optional [actionLabel]/[onAction] renders a small labelled button (the
/// portrait's "Replace portrait"). A [badge] pill (bottom-left) plus a
/// [highlighted] ring surface the current state ("Showing" this chat, or the
/// prime/default emotion) — the parent picks [badgeColor] so the two never share
/// a visual language.
class AvatarTile extends StatelessWidget {
  const AvatarTile({
    super.key,
    required this.imageFile,
    required this.starred,
    required this.onStar,
    this.caption,
    this.onDelete,
    this.onTap,
    this.badge,
    this.badgeColor,
    this.highlighted = false,
    this.actionLabel,
    this.onAction,
    this.onCaptionTap,
    this.imageVersion = 0,
  });

  /// The image to display (already resolved to its `looks/` or `avatars/` file).
  final File imageFile;

  /// Bumped by the gallery when file bytes change under a stable path (portrait
  /// overwrite). Keys the [Image.file] so Flutter does not keep a stale frame.
  final int imageVersion;

  /// Bottom caption — a look name, "Portrait", or the emotion label.
  final String? caption;

  /// Whether this tile holds the one ★ canonical-avatar star.
  final bool starred;

  /// Toggle the ★ on this tile (set it as the canonical avatar).
  final VoidCallback onStar;

  /// Remove this tile. Null → no ✕ (the portrait can't be deleted).
  final VoidCallback? onDelete;

  /// Body tap — "use in this chat" (looks) or "set default emotion"
  /// (expressions). Null → the body isn't interactive.
  final VoidCallback? onTap;

  /// Bottom-left status pill ("Showing" / "Default"). Null → none.
  final String? badge;

  /// Colour of the [badge] pill + the [highlighted] ring — the parent chooses it
  /// so "Showing" (this chat) and "Default" (prime emotion) read differently.
  final Color? badgeColor;

  /// Draw a selection ring (the currently-shown / prime tile).
  final bool highlighted;

  /// A small labelled button on the tile (the portrait's "Replace portrait").
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Makes the [caption] a tappable chip (re-label an expression's emotion).
  final VoidCallback? onCaptionTap;

  @override
  Widget build(BuildContext context) {
    final ring = badgeColor ?? AppColors.formMasterAccent;
    final scrim = AppColors.resolve(
      context,
      Colors.black.withValues(alpha: 0.55),
      Colors.black.withValues(alpha: 0.42),
    );
    final onScrim = AppColors.resolve(context, Colors.white, Colors.white);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? ring
              : AppColors.borderOf(context).withValues(alpha: 0.6),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [BoxShadow(color: ring.withValues(alpha: 0.25), blurRadius: 10)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image (or a graceful missing-file placeholder).
            // Key includes [imageVersion] so in-place portrait overwrites
            // (delete → promote look) drop the cached blank/old face.
            Image.file(
              imageFile,
              key: ValueKey('${imageFile.path}#$imageVersion'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              gaplessPlayback: false,
              errorBuilder: (_, _, _) => Container(
                color: AppColors.surfaceContainerOf(context),
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.iconSecondary(context),
                  size: 30,
                ),
              ),
            ),

            // Body tap (select / set-prime).
            if (onTap != null)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onTap),
                ),
              ),

            // ★ star, top-left.
            Positioned(
              top: 5,
              left: 5,
              child: _circleButton(
                icon: starred ? Icons.star_rounded : Icons.star_border_rounded,
                tooltip: starred ? 'Canonical avatar' : 'Set as canonical avatar',
                onTap: onStar,
                bg: starred ? AppColors.formMasterAccent : scrim,
                fg: onScrim,
              ),
            ),

            // ✕ delete, top-right.
            if (onDelete != null)
              Positioned(
                top: 5,
                right: 5,
                child: _circleButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Delete',
                  onTap: onDelete!,
                  bg: scrim,
                  fg: onScrim,
                ),
              ),

            // Status badge, bottom-left.
            if (badge != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: ring,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: onScrim,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

            // Caption gradient, bottom. Tappable (re-label) when onCaptionTap set.
            if (caption != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _caption(context, scrim, onScrim),
              ),

            // Optional labelled action (portrait "Replace portrait").
            if (actionLabel != null && onAction != null)
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Material(
                  color: scrim,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_outlined, size: 12, color: onScrim),
                          const SizedBox(width: 4),
                          Text(
                            actionLabel!,
                            style: TextStyle(
                              color: onScrim,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _caption(BuildContext context, Color scrim, Color onScrim) {
    final content = Container(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, scrim],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              caption!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onScrim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onCaptionTap != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded, size: 14, color: onScrim),
          ],
        ],
      ),
    );
    if (onCaptionTap == null) return IgnorePointer(child: content);
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onCaptionTap, child: content),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color bg,
    required Color fg,
  }) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        iconSize: 15,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        icon: Icon(icon, color: fg),
      ),
    );
  }
}
